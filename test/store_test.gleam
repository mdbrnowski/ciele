import ciele/store.{Snapshot}
import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/option.{None, Some}
import gleam/time/timestamp.{type Timestamp}
import simplifile

// encode/1 and parse/1

pub fn round_trip_preserves_snapshots_test() {
  let seen =
    Snapshot(
      body: Some("<html><body>hello</body></html>"),
      fetched_at: Some(at(1_758_000_000)),
      errors: 0,
    )
  let missing = Snapshot(body: None, fetched_at: None, errors: 2)
  let snapshots =
    dict.from_list([#("gleam.run", seen), #("erlang.org", missing)])

  assert store.parse(store.encode(snapshots)) == Ok(snapshots)
}

pub fn round_trip_preserves_an_empty_state_test() {
  assert store.parse(store.encode(dict.new())) == Ok(dict.new())
}

pub fn round_trip_escapes_page_bodies_test() {
  let tricky =
    Snapshot(
      body: Some("<p class=\"x\">quote \" and\nnewline</p>"),
      fetched_at: None,
      errors: 0,
    )
  let snapshots = dict.from_list([#("gleam.run", tricky)])

  assert store.parse(store.encode(snapshots)) == Ok(snapshots)
}

// parse/1

pub fn parse_rejects_malformed_json_test() {
  assert is_parse_error(store.parse("not json"))
}

pub fn parse_rejects_an_empty_document_test() {
  assert is_parse_error(store.parse(""))
}

pub fn parse_rejects_a_missing_field_test() {
  assert is_parse_error(store.parse("{\"version\":1}"))
}

pub fn parse_rejects_a_wrong_field_type_test() {
  assert is_parse_error(store.parse(document("\"hi\"", "null", "\"none\"")))
}

pub fn parse_rejects_an_unknown_version_test() {
  assert store.parse("{\"version\":2,\"pages\":[]}")
    == Error(store.UnsupportedVersion(2))
}

pub fn parse_keeps_a_page_without_a_body_test() {
  let expected = Snapshot(body: None, fetched_at: None, errors: 2)

  assert store.parse(document("null", "null", "2"))
    == Ok(dict.from_list([#("gleam.run", expected)]))
}

pub fn parse_ignores_an_unreadable_timestamp_test() {
  let expected = Snapshot(body: Some("hi"), fetched_at: None, errors: 0)

  assert store.parse(document("\"hi\"", "\"nonsense\"", "0"))
    == Ok(dict.from_list([#("gleam.run", expected)]))
}

// save/1 and load/0

pub fn load_without_a_file_is_empty_test() {
  assert in_scratch_directory(store.load) == Ok(dict.new())
}

pub fn save_then_load_round_trips_test() {
  let pages =
    dict.from_list([
      #("gleam.run", Snapshot(body: Some("hi"), fetched_at: None, errors: 2)),
    ])
  let loaded =
    in_scratch_directory(fn() {
      let _ = store.save(pages)
      store.load()
    })
  assert loaded == Ok(pages)
}

pub fn failed_save_removes_the_temp_file_test() {
  let #(saved, temp_file) =
    in_scratch_directory(fn() {
      // A directory in the way makes the final rename fail.
      let _ = simplifile.create_directory_all("data/state.json")
      #(store.save(dict.new()), simplifile.is_file("data/state.json.tmp"))
    })
  assert saved != Ok(Nil)
  assert temp_file == Ok(False)
}

// describe_age/2

pub fn describe_age_in_days_test() {
  assert store.describe_age(at(0), at(3 * 86_400)) == "3 days ago"
}

pub fn describe_age_of_a_single_day_test() {
  assert store.describe_age(at(0), at(86_400)) == "1 day ago"
}

pub fn describe_age_in_hours_test() {
  assert store.describe_age(at(0), at(7200)) == "2 hours ago"
}

pub fn describe_age_in_minutes_test() {
  assert store.describe_age(at(0), at(125)) == "2 minutes ago"
}

pub fn describe_age_below_a_minute_test() {
  assert store.describe_age(at(0), at(30)) == "just now"
}

pub fn describe_age_of_a_fresh_snapshot_test() {
  assert store.describe_age(at(100), at(100)) == "just now"
}

pub fn describe_age_of_a_snapshot_from_the_future_test() {
  assert store.describe_age(at(500), at(100)) == "just now"
}

/// Run `body` from an empty directory, so it never touches the real state
/// file.
fn in_scratch_directory(body: fn() -> a) -> a {
  let assert Ok(root) = simplifile.current_directory()
  let scratch = root <> "/build/store_test"
  let _ = simplifile.delete(scratch)
  let assert Ok(Nil) = simplifile.create_directory_all(scratch)
  set_cwd(scratch)
  let result = body()
  set_cwd(root)
  let _ = simplifile.delete(scratch)
  result
}

@external(erlang, "file", "set_cwd")
fn set_cwd(directory: String) -> Dynamic

fn at(seconds: Int) -> Timestamp {
  timestamp.from_unix_seconds(seconds)
}

/// A stored document holding one page, its fields spelled out as JSON so the
/// values a decoder should reject can be written too.
fn document(body: String, fetched_at: String, errors: String) -> String {
  "{\"version\":1,\"pages\":[{\"url\":\"gleam.run\",\"body\":"
  <> body
  <> ",\"fetched_at\":"
  <> fetched_at
  <> ",\"errors\":"
  <> errors
  <> "}]}"
}

fn is_parse_error(result: Result(a, store.StoreError)) -> Bool {
  case result {
    Error(store.ParseError(_)) -> True
    _ -> False
  }
}
