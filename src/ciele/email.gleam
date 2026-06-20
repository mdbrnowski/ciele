//// Building and sending change-notification emails through the Resend API.

import ciele/config.{type Config}
import envoy
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json
import gleam/string
import logging

/// Send a notification email containing `diff` for `domain`.
///
/// In dry-run mode the email is logged to the console instead of being sent.
/// Otherwise, when `RESEND_API_KEY` is not set the email is skipped and an
/// error is logged.
pub fn send(diff: String, domain: String, config: Config) -> Nil {
  case config.dry_run {
    True -> log_email(diff, domain, config)
    False ->
      case envoy.get("RESEND_API_KEY") {
        Error(_) ->
          logging.log(
            logging.Error,
            "RESEND_API_KEY not set, skipping email for " <> domain,
          )
        Ok(api_key) -> dispatch(api_key, diff, domain, config)
      }
  }
}

/// Log the email that would have been sent, used in dry-run mode.
fn log_email(diff: String, domain: String, config: Config) -> Nil {
  logging.log(
    logging.Notice,
    "[dry-run] Email for "
      <> domain
      <> " not sent. Would send:\n"
      <> "From: Ciele <"
      <> config.sender_email_address
      <> ">\n"
      <> "To: "
      <> config.email_address
      <> "\n"
      <> "Subject: Ciele: change detected for "
      <> remove_https(domain)
      <> "\n\n"
      <> build_html(diff, domain),
  )
}

fn dispatch(
  api_key: String,
  diff: String,
  domain: String,
  config: Config,
) -> Nil {
  let request =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_scheme(http.Https)
    |> request.set_host("api.resend.com")
    |> request.set_path("/emails")
    |> request.set_header("authorization", "Bearer " <> api_key)
    |> request.set_header("content-type", "application/json")
    |> request.set_body(json.to_string(build_payload(diff, domain, config)))

  case httpc.send(request) {
    Ok(response) ->
      case response.status >= 200 && response.status < 300 {
        True ->
          logging.log(
            logging.Notice,
            "Sent change email for "
              <> domain
              <> " (status "
              <> int.to_string(response.status)
              <> ")",
          )
        False ->
          logging.log(
            logging.Error,
            "Email for "
              <> domain
              <> " failed with status "
              <> int.to_string(response.status),
          )
      }
    Error(error) ->
      logging.log(
        logging.Error,
        "Failed to send email for " <> domain <> ": " <> string.inspect(error),
      )
  }
}

/// Build the JSON payload expected by the Resend `/emails` endpoint.
pub fn build_payload(
  diff: String,
  domain: String,
  config: Config,
) -> json.Json {
  json.object([
    #("from", json.string("Ciele <" <> config.sender_email_address <> ">")),
    #("to", json.array([config.email_address], json.string)),
    #(
      "subject",
      json.string("Ciele: change detected for " <> remove_https(domain)),
    ),
    #("html", json.string(build_html(diff, domain))),
    #("reply_to", json.string(config.sender_email_address)),
  ])
}

/// Build the HTML body of the notification email.
pub fn build_html(diff: String, domain: String) -> String {
  "<p>Change detected for "
  <> escape_html(domain)
  <> "</p><pre style=\"white-space:pre-wrap\">"
  <> escape_html(diff)
  <> "</pre>"
}

/// Strip a leading `http://` or `https://` scheme from `url`.
pub fn remove_https(url: String) -> String {
  case url {
    "https://" <> rest -> rest
    "http://" <> rest -> rest
    _ -> url
  }
}

/// Escape the characters that are significant in HTML text content.
pub fn escape_html(text: String) -> String {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
}
