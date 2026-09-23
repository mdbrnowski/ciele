//// The long-running actor that periodically fetches every configured domain,
//// compares it against the previously seen content, and triggers a diff email
//// when something changes.

import ciele/config.{type Config, type Page}
import ciele/diff
import ciele/email
import ciele/store.{type Snapshot, Snapshot}
import ciele/url
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/string
import gleam/time/timestamp.{type Timestamp}
import logging

/// Six hours, in milliseconds.
const interval = 21_600_000

/// How long the initialiser has to read the state file, in milliseconds.
const init_timeout = 10_000

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
    /// The last seen snapshot for each domain, keyed by its configured URL.
    pages: Dict(String, Snapshot),
  )
}

/// Start the server, restoring the previous run's snapshots. The first check
/// is scheduled to run immediately.
pub fn start() -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(init_timeout, fn(self) {
    process.send(self, CheckSites)
    State(self:, pages: restore())
    |> actor.initialised
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle_message)
  |> actor.start
}

/// Read the persisted snapshots, falling back to an empty set.
fn restore() -> Dict(String, Snapshot) {
  case store.load() {
    Ok(pages) -> {
      logging.log(
        logging.Notice,
        "Restored "
          <> int.to_string(dict.size(pages))
          <> " snapshots from "
          <> store.path()
          <> since(last_fetch(pages)),
      )
      pages
    }
    Error(error) -> {
      logging.log(
        logging.Warning,
        "Starting without previous snapshots: " <> store.describe_error(error),
      )
      dict.new()
    }
  }
}

/// Write the snapshots to disk. A failure is logged and retried next cycle.
fn persist(pages: Dict(String, Snapshot)) -> Nil {
  case store.save(pages) {
    Ok(Nil) ->
      logging.log(
        logging.Info,
        "Saved "
          <> int.to_string(dict.size(pages))
          <> " snapshots to "
          <> store.path(),
      )
    Error(error) -> logging.log(logging.Error, store.describe_error(error))
  }
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
      let urls = list.map(config.pages, fn(page) { page.url })
      let removed =
        dict.keys(state.pages)
        |> list.filter(fn(domain) { !list.contains(urls, domain) })
      list.each(removed, fn(domain) {
        logging.log(logging.Notice, "Domain removed from config: " <> domain)
      })

      logging.log(
        logging.Notice,
        "Loaded "
          <> int.to_string(list.length(config.pages))
          <> " domains to check. Starting checks...",
      )

      let state = State(..state, pages: dict.drop(state.pages, removed))
      let state =
        list.fold(config.pages, state, fn(state, page) {
          check_and_compare(page, state, config)
        })

      persist(state.pages)

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

fn check_and_compare(page: Page, state: State, config: Config) -> State {
  let domain = page.url
  let url = url.with_scheme(domain)
  logging.log(logging.Info, "Checking domain: " <> url)

  case fetch_body(url) {
    Ok(body) -> {
      maybe_log_change(page, body, state.pages, config)
      State(
        ..state,
        pages: dict.insert(
          state.pages,
          domain,
          Snapshot(
            body: Some(body),
            fetched_at: Some(timestamp.system_time()),
            errors: 0,
          ),
        ),
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
  // Keep the last body we saw: the page may come back.
  let snapshot = case dict.get(state.pages, domain) {
    Ok(snapshot) -> snapshot
    Error(_) -> Snapshot(body: None, fetched_at: None, errors: 0)
  }
  let count = snapshot.errors + 1

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

  State(
    ..state,
    pages: dict.insert(state.pages, domain, Snapshot(..snapshot, errors: count)),
  )
}

/// Compare the freshly fetched `body` for `page` against the raw body of its
/// last snapshot.
fn maybe_log_change(
  page: Page,
  body: String,
  pages: Dict(String, Snapshot),
  config: Config,
) -> Nil {
  let domain = page.url
  let new = comparable_content(body, page.ignore, page.ignore_classes)

  case dict.get(pages, domain) {
    Ok(Snapshot(body: Some(previous), fetched_at:, ..)) -> {
      let old = comparable_content(previous, page.ignore, page.ignore_classes)
      case old == new {
        True -> logging.log(logging.Info, "No change for " <> domain)
        False -> {
          logging.log(
            logging.Notice,
            "Content changed for "
              <> domain
              <> since(fetched_at)
              <> " ("
              <> int.to_string(string.byte_size(old))
              <> " -> "
              <> int.to_string(string.byte_size(new))
              <> " bytes)",
          )
          notify_change(old, new, domain, config)
        }
      }
    }
    _ ->
      logging.log(
        logging.Notice,
        "First check recorded for "
          <> domain
          <> " ("
          <> int.to_string(string.byte_size(new))
          <> " bytes)",
      )
  }
}

/// Render the age of a snapshot, for example " (last seen 3 days ago)".
fn since(fetched_at: Option(Timestamp)) -> String {
  case fetched_at {
    None -> ""
    Some(moment) ->
      " (last seen "
      <> store.describe_age(moment, timestamp.system_time())
      <> ")"
  }
}

/// The most recent fetch among `pages`, or `None` when nothing was restored:
/// how stale the state read back from disk is.
fn last_fetch(pages: Dict(String, Snapshot)) -> Option(Timestamp) {
  dict.values(pages)
  |> list.filter_map(fn(snapshot) { option.to_result(snapshot.fetched_at, Nil) })
  |> list.max(timestamp.compare)
  |> option.from_result
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
/// HTML document, return its `<body>` with every `<script>` and every element
/// matching one of the `ignore` CSS selectors removed, pretty-printed via
/// Floki. When `ignore_classes` is `True`, `class` attributes are stripped from
/// every remaining tag too.
pub fn comparable_content(
  content: String,
  ignore: List(String),
  ignore_classes: Bool,
) -> String {
  case floki_comparable_content(content, ignore, ignore_classes) {
    Ok(body) -> body
    Error(_) -> content
  }
}

@external(erlang, "Elixir.Ciele.Html", "comparable_content")
fn floki_comparable_content(
  content: String,
  ignore: List(String),
  ignore_classes: Bool,
) -> Result(String, Nil)
