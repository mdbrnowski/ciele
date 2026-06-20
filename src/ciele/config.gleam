//// Loading and validation of the `config/config.yaml` file.

import glaml
import gleam/list
import gleam/result
import gleam/string

const config_file = "config/config.yaml"

/// The application configuration, as read from `config/config.yaml`.
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
  /// The file could not be read or parsed as YAML.
  ParseError(glaml.YamlError)
  /// A required key is missing from the document.
  MissingField(String)
  /// A key is present but has the wrong type.
  InvalidField(String)
}

/// Render a `ConfigError` as a human-readable message.
pub fn describe_error(error: ConfigError) -> String {
  case error {
    ParseError(yaml_error) ->
      "Could not parse " <> config_file <> ": " <> string.inspect(yaml_error)
    MissingField(key) ->
      "Missing required field '" <> key <> "' in " <> config_file
    InvalidField(key) ->
      "Field '" <> key <> "' in " <> config_file <> " has an invalid type"
  }
}

/// Read and validate `config/config.yaml`.
pub fn load() -> Result(Config, ConfigError) {
  use documents <- result.try(
    glaml.parse_file(config_file) |> result.map_error(ParseError),
  )

  let root = case documents {
    [document, ..] -> glaml.document_root(document)
    [] -> glaml.NodeNil
  }

  use email_address <- result.try(get_string(root, "email_address"))
  use sender_email_address <- result.try(get_string(
    root,
    "sender_email_address",
  ))
  use domains <- result.try(get_string_list(root, "domains"))
  use dry_run <- result.try(get_bool(root, "dry_run", or: False))

  Ok(Config(email_address:, sender_email_address:, domains:, dry_run:))
}

fn get_node(root: glaml.Node, key: String) -> Result(glaml.Node, ConfigError) {
  glaml.select_sugar(root, key) |> result.replace_error(MissingField(key))
}

fn get_string(root: glaml.Node, key: String) -> Result(String, ConfigError) {
  case get_node(root, key) {
    Ok(glaml.NodeStr(value)) -> Ok(value)
    Ok(_) -> Error(InvalidField(key))
    Error(error) -> Error(error)
  }
}

fn get_bool(
  root: glaml.Node,
  key: String,
  or default: Bool,
) -> Result(Bool, ConfigError) {
  case glaml.select_sugar(root, key) {
    // Optional: a missing key falls back to the default.
    Error(_) -> Ok(default)
    Ok(glaml.NodeBool(value)) -> Ok(value)
    Ok(_) -> Error(InvalidField(key))
  }
}

fn get_string_list(
  root: glaml.Node,
  key: String,
) -> Result(List(String), ConfigError) {
  case get_node(root, key) {
    Ok(glaml.NodeSeq(nodes)) ->
      list.try_map(nodes, fn(node) {
        case node {
          glaml.NodeStr(value) -> Ok(value)
          _ -> Error(InvalidField(key))
        }
      })
    Ok(_) -> Error(InvalidField(key))
    Error(error) -> Error(error)
  }
}
