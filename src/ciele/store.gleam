//// Persistence of the last seen page snapshots, so a restart does not lose
//// the content every domain is compared against.

import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import simplifile

const directory = "data"

const state_file = "data/state.json"

/// Written here, then renamed over `state_file`.
const temp_file = "data/state.json.tmp"

/// Bumped whenever the format changes in a way earlier releases cannot read.
const version = 1

/// The last seen state of a single monitored page.
pub type Snapshot {
  Snapshot(
    /// The raw body as fetched. `None` until the first successful fetch.
    body: Option(String),
    /// When `body` was fetched.
    fetched_at: Option(Timestamp),
    /// Consecutive 404 count.
    errors: Int,
  )
}

/// Everything that can go wrong while reading or writing the state file.
pub type StoreError {
  /// The file could not be read.
  ReadError(simplifile.FileError)
  /// The file could not be written.
  WriteError(String)
  /// The file could not be parsed as JSON.
  ParseError(json.DecodeError)
  /// The file was written in a format this release does not understand.
  UnsupportedVersion(Int)
}

/// Render a `StoreError` as a human-readable message.
pub fn describe_error(error: StoreError) -> String {
  case error {
    ReadError(file_error) ->
      "Could not read "
      <> state_file
      <> ": "
      <> simplifile.describe_error(file_error)
    WriteError(reason) -> "Could not write " <> state_file <> ": " <> reason
    ParseError(parse_error) ->
      "Could not parse " <> state_file <> ": " <> string.inspect(parse_error)
    UnsupportedVersion(found) ->
      "Unsupported version "
      <> int.to_string(found)
      <> " in "
      <> state_file
      <> ", expected "
      <> int.to_string(version)
  }
}

/// Where the snapshots are persisted, relative to the working directory.
pub fn path() -> String {
  state_file
}

/// Read the persisted snapshots. A missing file is a normal first run.
pub fn load() -> Result(Dict(String, Snapshot), StoreError) {
  case simplifile.read(state_file) {
    Error(simplifile.Enoent) -> Ok(dict.new())
    Error(file_error) -> Error(ReadError(file_error))
    Ok(source) -> parse(source)
  }
}

/// Persist `snapshots` atomically: write to a temporary file, flush, rename.
pub fn save(snapshots: Dict(String, Snapshot)) -> Result(Nil, StoreError) {
  let written = {
    use _ <- result.try(
      simplifile.create_directory_all(directory)
      |> result.map_error(describe_write_error),
    )
    use _ <- result.try(
      write_sync(temp_file, encode(snapshots)) |> result.map_error(WriteError),
    )
    simplifile.rename(at: temp_file, to: state_file)
    |> result.map_error(describe_write_error)
  }

  case written {
    Ok(Nil) -> Ok(Nil)
    // Never leave a half-written file behind to be renamed by the next run.
    Error(error) -> {
      let _ = simplifile.delete(temp_file)
      Error(error)
    }
  }
}

fn describe_write_error(error: simplifile.FileError) -> StoreError {
  WriteError(simplifile.describe_error(error))
}

/// Write `contents` to `path`, flushed to disk, so the rename in `save` cannot
/// be committed ahead of the data.
@external(erlang, "ciele_ffi", "write_sync")
fn write_sync(path: String, contents: String) -> Result(Nil, String)

/// Encode `snapshots` as the JSON document kept on disk.
pub fn encode(snapshots: Dict(String, Snapshot)) -> String {
  json.object([
    #("version", json.int(version)),
    #("pages", json.array(dict.to_list(snapshots), encode_page)),
  ])
  |> json.to_string
}

fn encode_page(entry: #(String, Snapshot)) -> Json {
  let #(url, snapshot) = entry
  json.object([
    #("url", json.string(url)),
    #("body", json.nullable(snapshot.body, json.string)),
    #(
      "fetched_at",
      json.nullable(option.map(snapshot.fetched_at, to_rfc3339), json.string),
    ),
    #("errors", json.int(snapshot.errors)),
  ])
}

fn to_rfc3339(moment: Timestamp) -> String {
  timestamp.to_rfc3339(moment, duration.seconds(0))
}

/// Decode the JSON document kept on disk.
pub fn parse(source: String) -> Result(Dict(String, Snapshot), StoreError) {
  use #(found, pages) <- result.try(
    json.parse(from: source, using: document_decoder())
    |> result.map_error(ParseError),
  )

  case found == version {
    False -> Error(UnsupportedVersion(found))
    True -> Ok(dict.from_list(pages))
  }
}

fn document_decoder() -> Decoder(#(Int, List(#(String, Snapshot)))) {
  use found <- decode.field("version", decode.int)
  use pages <- decode.field("pages", decode.list(page_decoder()))
  decode.success(#(found, pages))
}

fn page_decoder() -> Decoder(#(String, Snapshot)) {
  use url <- decode.field("url", decode.string)
  use body <- decode.field("body", decode.optional(decode.string))
  use fetched_at <- decode.field("fetched_at", decode.optional(decode.string))
  use errors <- decode.field("errors", decode.int)
  decode.success(#(
    url,
    Snapshot(body:, fetched_at: parse_timestamp(fetched_at), errors:),
  ))
}

/// An unreadable timestamp is dropped rather than failing the whole file.
fn parse_timestamp(value: Option(String)) -> Option(Timestamp) {
  use text <- option.then(value)
  timestamp.parse_rfc3339(text) |> option.from_result
}

/// Render how long ago a snapshot was taken, for example "3 days ago".
pub fn describe_age(taken: Timestamp, now: Timestamp) -> String {
  case timestamp.difference(taken, now) |> duration.approximate {
    #(amount, _) if amount < 1 -> "just now"
    #(amount, duration.Year) -> ago(amount, "year")
    #(amount, duration.Month) -> ago(amount, "month")
    #(amount, duration.Week) -> ago(amount, "week")
    #(amount, duration.Day) -> ago(amount, "day")
    #(amount, duration.Hour) -> ago(amount, "hour")
    #(amount, duration.Minute) -> ago(amount, "minute")
    _ -> "just now"
  }
}

fn ago(amount: Int, unit: String) -> String {
  case amount {
    1 -> "1 " <> unit <> " ago"
    _ -> int.to_string(amount) <> " " <> unit <> "s ago"
  }
}
