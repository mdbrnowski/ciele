//// Loading and validation of the `config/config.toml` file.

import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string
import simplifile
import tom.{type Toml}

const config_file = "config/config.toml"

/// A single monitored page: the URL to check, the CSS selectors whose matching
/// elements are stripped before comparison (`ignore`), and the attributes
/// stripped from every remaining tag (`ignore_attributes`).
pub type Page {
  Page(url: String, ignore: List(String), ignore_attributes: List(String))
}

/// The application configuration, as read from `config/config.toml`.
pub type Config {
  Config(
    email_address: String,
    sender_email_address: String,
    pages: List(Page),
    /// When `True`, the app does not require `RESEND_API_KEY` and logs the
    /// emails it would send to the console instead of sending them. Optional,
    /// defaults to `False`.
    dry_run: Bool,
    /// Notices about deprecated options that are still honoured but should be
    /// migrated.
    warnings: List(String),
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
  parse(source)
}

/// Parse and validate the contents of a config file.
pub fn parse(source: String) -> Result(Config, ConfigError) {
  use document <- result.try(tom.parse(source) |> result.map_error(ParseError))

  use email_address <- result.try(get_string(document, "email_address"))
  use sender_email_address <- result.try(get_string(
    document,
    "sender_email_address",
  ))
  use #(pages, warnings) <- result.try(get_pages(document, "domains"))
  use dry_run <- result.try(get_bool(document, "dry_run", or: False))

  Ok(Config(email_address:, sender_email_address:, pages:, dry_run:, warnings:))
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

/// Parse the monitored pages from `key`, along with any deprecation warnings.
/// Each array element is either a bare string or an inline table with a `url`
/// and optional `ignore` and `ignore_attributes`.
fn get_pages(
  document: Dict(String, Toml),
  key: String,
) -> Result(#(List(Page), List(String)), ConfigError) {
  use nodes <- result.try(
    tom.get_array(document, [key]) |> result.map_error(map_get_error(_, key)),
  )
  use parsed <- result.try(
    list.try_map(nodes, fn(node) {
      case node {
        tom.String(url) ->
          Ok(#(Page(url:, ignore: [], ignore_attributes: []), []))
        tom.Table(fields) | tom.InlineTable(fields) -> parse_page(fields)
        _ -> Error(InvalidField(key))
      }
    }),
  )
  let #(pages, warnings) = list.unzip(parsed)
  Ok(#(pages, list.flatten(warnings)))
}

fn parse_page(
  fields: Dict(String, Toml),
) -> Result(#(Page, List(String)), ConfigError) {
  use url <- result.try(get_string(fields, "url"))
  use ignore <- result.try(get_string_list(fields, "ignore", or: []))
  use ignore_attributes <- result.try(
    get_string_list(fields, "ignore_attributes", or: []),
  )

  // Deprecated: `ignore_classes = true` is shorthand for ignoring `class`.
  use ignore_classes <- result.try(get_bool(fields, "ignore_classes", or: False))
  let ignore_attributes = case ignore_classes {
    True -> ["class", ..ignore_attributes]
    False -> ignore_attributes
  }
  let warnings = case dict.has_key(fields, "ignore_classes") {
    True -> [
      "'ignore_classes' (for "
      <> url
      <> ") is deprecated, use 'ignore_attributes' instead",
    ]
    False -> []
  }

  Ok(#(Page(url:, ignore:, ignore_attributes:), warnings))
}

fn get_string_list(
  document: Dict(String, Toml),
  key: String,
  or default: List(String),
) -> Result(List(String), ConfigError) {
  case tom.get_array(document, [key]) {
    Error(tom.NotFound(_)) -> Ok(default)
    result -> {
      use nodes <- result.try(result |> result.map_error(map_get_error(_, key)))
      list.try_map(nodes, fn(node) {
        case node {
          tom.String(value) -> Ok(value)
          _ -> Error(InvalidField(key))
        }
      })
    }
  }
}

fn map_get_error(error: tom.GetError, key: String) -> ConfigError {
  case error {
    tom.NotFound(_) -> MissingField(key)
    tom.WrongType(..) -> InvalidField(key)
  }
}
