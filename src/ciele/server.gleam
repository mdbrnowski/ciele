//// The long-running actor that periodically fetches every configured domain,
//// compares it against the previously seen content, and triggers a diff email
//// when something changes.

import ciele/config.{type Config}
import ciele/diff
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/otp/actor
import gleam/regexp
import gleam/string
import logging

/// Six hours, in milliseconds.
const interval = 21_600_000

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
    Error(error) -> panic as config.describe_error(error)
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
  let url = to_url(domain)
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
      diff.handle_diff(
        "[Previous content]\n",
        "404 Not Found\n",
        domain,
        config,
      )
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
      diff.handle_diff(old, body, domain, config)
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

/// Prefix `domain` with `https://` unless it already carries a scheme.
pub fn to_url(domain: String) -> String {
  case domain {
    "http://" <> _ | "https://" <> _ -> domain
    _ -> "https://" <> domain
  }
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
      case httpc.send_bits(request.set_body(request, <<>>)) {
        Ok(response) ->
          case response.status >= 200 && response.status < 400 {
            True -> Ok(decode_body(response.body))
            False -> Error(UnexpectedStatus(response.status))
          }
        Error(error) -> Error(RequestFailed(error))
      }
  }
}

/// Decode a response body into a string. Valid UTF-8 is kept as-is; pages with
/// the odd corrupt byte are decoded leniently, replacing only the invalid bytes
/// with `?` so the rest of the (readable) content survives into the diff email.
pub fn decode_body(body: BitArray) -> String {
  case bit_array.to_string(body) {
    Ok(text) -> text
    Error(_) -> lossy_utf8(body)
  }
}

@external(erlang, "encoding_ffi", "lossy_utf8")
fn lossy_utf8(body: BitArray) -> String

/// Extract the contents of the `<body>` element, falling back to the whole
/// document when there is no body. This is the part of a page worth comparing.
pub fn comparable_content(content: String) -> String {
  let assert Ok(re) =
    regexp.compile(
      "<body\\b[^>]*>([\\s\\S]*?)</body>",
      regexp.Options(case_insensitive: True, multi_line: False),
    )

  case regexp.scan(re, content) {
    [match, ..] ->
      case match.submatches {
        [Some(body), ..] -> body
        _ -> content
      }
    [] -> content
  }
}
