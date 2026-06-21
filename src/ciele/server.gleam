//// The long-running actor that periodically fetches every configured domain,
//// compares it against the previously seen content, and triggers a diff email
//// when something changes.

import ciele/config.{type Config}
import ciele/diff
import ciele/email
import ciele/url
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/string
import logging

/// Six hours, in milliseconds.
const interval = 21_600_000

/// Some hosts answer 403 to clients without a browser-like User-Agent.
const browser_user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
  <> "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

/// Messages the server understands.
pub type Message {
  /// Fetch every configured domain and compare it with the last seen content.
  CheckSites
}

type State {
  State(
    self: Subject(Message),
    /// The last seen comparable content for each domain.
    checks: Dict(String, String),
    /// Consecutive 404 counts per domain.
    errors: Dict(String, Int),
  )
}

/// Start the server. The first check is scheduled to run immediately.
pub fn start() -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self) {
    process.send(self, CheckSites)
    State(self:, checks: dict.new(), errors: dict.new())
    |> actor.initialised
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message {
    CheckSites -> {
      let state = check_sites(state)
      process.send_after(state.self, interval, CheckSites)
      actor.continue(state)
    }
  }
}

fn check_sites(state: State) -> State {
  case config.load() {
    Error(error) -> {
      logging.log(
        logging.Error,
        "Could not reload config, keeping previous domains: "
          <> config.describe_error(error),
      )
      state
    }
    Ok(config) -> {
      let removed =
        dict.keys(state.checks)
        |> list.filter(fn(domain) { !list.contains(config.domains, domain) })
      list.each(removed, fn(domain) {
        logging.log(logging.Notice, "Domain removed from config: " <> domain)
      })

      logging.log(
        logging.Notice,
        "Loaded "
          <> int.to_string(list.length(config.domains))
          <> " domains to check. Starting checks...",
      )

      let state = State(..state, checks: dict.drop(state.checks, removed))
      let state =
        list.fold(config.domains, state, fn(state, domain) {
          check_and_compare(domain, state, config)
        })

      logging.log(
        logging.Notice,
        "All domain checks completed. Scheduling next check in "
          <> int.to_string(interval / 1000)
          <> " s.",
      )
      state
    }
  }
}

fn check_and_compare(domain: String, state: State, config: Config) -> State {
  let url = url.with_scheme(domain)
  logging.log(logging.Info, "Checking domain: " <> url)

  case fetch_body(url) {
    Ok(body) -> {
      let comparable = comparable_content(body)
      maybe_log_change(domain, comparable, state.checks, config)
      State(
        ..state,
        checks: dict.insert(state.checks, domain, comparable),
        errors: dict.delete(state.errors, domain),
      )
    }
    Error(UnexpectedStatus(404)) -> handle_404(domain, state, config)
    Error(reason) -> {
      logging.log(
        logging.Warning,
        "Failed to fetch " <> url <> ": " <> string.inspect(reason),
      )
      state
    }
  }
}

fn handle_404(domain: String, state: State, config: Config) -> State {
  let count = case dict.get(state.errors, domain) {
    Ok(previous) -> previous + 1
    Error(_) -> 1
  }

  case count {
    1 -> logging.log(logging.Notice, "First 404 for " <> domain)
    2 -> {
      logging.log(logging.Notice, "Two consecutive 404 errors for " <> domain)
      notify_change("[Previous content]\n", "404 Not Found\n", domain, config)
    }
    _ ->
      logging.log(
        logging.Notice,
        "Subsequent 404 (" <> int.to_string(count) <> ") for " <> domain,
      )
  }

  State(..state, errors: dict.insert(state.errors, domain, count))
}

fn maybe_log_change(
  domain: String,
  body: String,
  checks: Dict(String, String),
  config: Config,
) -> Nil {
  case dict.get(checks, domain) {
    Ok(old) if old == body ->
      logging.log(logging.Info, "No change for " <> domain)
    Ok(old) -> {
      logging.log(
        logging.Notice,
        "Content changed for "
          <> domain
          <> " ("
          <> int.to_string(string.byte_size(old))
          <> " -> "
          <> int.to_string(string.byte_size(body))
          <> " bytes)",
      )
      notify_change(old, body, domain, config)
    }
    Error(_) ->
      logging.log(
        logging.Notice,
        "First check recorded for "
          <> domain
          <> " ("
          <> int.to_string(string.byte_size(body))
          <> " bytes)",
      )
  }
}

/// Diff `old` against `new`, log the result, and email a notification for
/// `domain`.
fn notify_change(
  old: String,
  new: String,
  domain: String,
  config: Config,
) -> Nil {
  let diff = diff.compute(old, new)
  logging.log(logging.Info, "Diff for " <> domain <> ":\n" <> diff)
  email.send(diff, domain, config)
}

/// Errors that can occur while fetching a page.
pub type FetchError {
  /// The URL could not be parsed.
  BadUrl
  /// The server responded with a status outside the 2xx–3xx range.
  UnexpectedStatus(Int)
  /// The request itself failed (connection, TLS, timeout, ...).
  RequestFailed(httpc.HttpError)
}

fn fetch_body(url: String) -> Result(String, FetchError) {
  case request.to(url) {
    Error(_) -> Error(BadUrl)
    Ok(request) ->
      case
        request
        |> request.set_header("user-agent", browser_user_agent)
        |> request.set_body(<<>>)
        |> httpc.send_bits
      {
        Ok(response) -> handle_response(response.status, response.body)
        // Some hosts sit behind a middlebox that drops Erlang's default TLS 1.3
        // handshake, surfacing as `FailedToConnect(_, Posix("closed"))`. Retry
        // once forcing TLS 1.2; keep the original error if that fails too.
        Error(error) ->
          case fetch_tls12(url, browser_user_agent) {
            Ok(#(status, body)) -> handle_response(status, body)
            Error(_) -> Error(RequestFailed(error))
          }
      }
  }
}

fn handle_response(status: Int, body: BitArray) -> Result(String, FetchError) {
  case status >= 200 && status < 400 {
    True -> Ok(decode_body(body))
    False -> Error(UnexpectedStatus(status))
  }
}

@external(erlang, "ciele_ffi", "fetch_tls12")
fn fetch_tls12(url: String, user_agent: String) -> Result(#(Int, BitArray), Nil)

/// Decode a response body into a string. Valid UTF-8 is kept as-is; pages with
/// the odd corrupt byte are decoded leniently, replacing only the invalid bytes
/// with `?` so the rest of the (readable) content survives into the diff email.
pub fn decode_body(body: BitArray) -> String {
  case bit_array.to_string(body) {
    Ok(text) -> text
    Error(_) -> lossy_utf8(body)
  }
}

@external(erlang, "ciele_ffi", "lossy_utf8")
fn lossy_utf8(body: BitArray) -> String

/// Reduce a page to the part worth comparing: when `content` is a parseable
/// HTML document, return its `<body>` with every `<script>` removed,
/// pretty-printed via Floki. Anything that is not such a document (no body,
/// unparseable) falls back to comparing the raw content unchanged.
pub fn comparable_content(content: String) -> String {
  case floki_comparable_content(content) {
    Ok(body) -> body
    Error(_) -> content
  }
}

@external(erlang, "Elixir.Ciele.Html", "comparable_content")
fn floki_comparable_content(content: String) -> Result(String, Nil)
