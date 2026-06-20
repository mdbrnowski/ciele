//// Loading and validation of the `config/config.toml` file.

import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string
import simplifile
import tom.{type Toml}

const config_file = "config/config.toml"

/// The application configuration, as read from `config/config.toml`.
pub type Config {
  Config(
    email_address: String,
    sender_email_address: String,
    domains: List(String),
    /// When `True`, the app does not require `RESEND_API_KEY` and logs the
    /// emails it would send to the console instead of sending them. Optional,
    /// defaults to `False`.
    dry_run: Bool,
  )
}

/// Everything that can go wrong while reading the configuration.
pub type ConfigError {
  /// The file could not be read.
  ReadError(simplifile.FileError)
  /// The file could not be parsed as TOML.
  ParseError(tom.ParseError)
  /// A required key is missing from the document.
  MissingField(String)
  /// A key is present but has the wrong type.
  InvalidField(String)
}

/// Render a `ConfigError` as a human-readable message.
pub fn describe_error(error: ConfigError) -> String {
  case error {
    ReadError(file_error) ->
      "Could not read " <> config_file <> ": " <> string.inspect(file_error)
    ParseError(parse_error) ->
      "Could not parse " <> config_file <> ": " <> string.inspect(parse_error)
    MissingField(key) ->
      "Missing required field '" <> key <> "' in " <> config_file
    InvalidField(key) ->
      "Field '" <> key <> "' in " <> config_file <> " has an invalid type"
  }
}

/// Read and validate `config/config.toml`.
pub fn load() -> Result(Config, ConfigError) {
  use source <- result.try(
    simplifile.read(config_file) |> result.map_error(ReadError),
  )
  use document <- result.try(tom.parse(source) |> result.map_error(ParseError))

  use email_address <- result.try(get_string(document, "email_address"))
  use sender_email_address <- result.try(get_string(
    document,
    "sender_email_address",
  ))
  use domains <- result.try(get_string_list(document, "domains"))
  use dry_run <- result.try(get_bool(document, "dry_run", or: False))

  Ok(Config(email_address:, sender_email_address:, domains:, dry_run:))
}

fn get_string(
  document: Dict(String, Toml),
  key: String,
) -> Result(String, ConfigError) {
  tom.get_string(document, [key]) |> result.map_error(map_get_error(_, key))
}

fn get_bool(
  document: Dict(String, Toml),
  key: String,
  or default: Bool,
) -> Result(Bool, ConfigError) {
  case tom.get_bool(document, [key]) {
    Error(tom.NotFound(_)) -> Ok(default)
    result -> result |> result.map_error(map_get_error(_, key))
  }
}

fn get_string_list(
  document: Dict(String, Toml),
  key: String,
) -> Result(List(String), ConfigError) {
  use nodes <- result.try(
    tom.get_array(document, [key]) |> result.map_error(map_get_error(_, key)),
  )
  list.try_map(nodes, fn(node) {
    case node {
      tom.String(value) -> Ok(value)
      _ -> Error(InvalidField(key))
    }
  })
}

fn map_get_error(error: tom.GetError, key: String) -> ConfigError {
  case error {
    tom.NotFound(_) -> MissingField(key)
    tom.WrongType(..) -> InvalidField(key)
  }
}
