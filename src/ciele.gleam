//// Ciele monitors a set of static websites and emails you whenever one of
//// them changes.

import ciele/config
import ciele/server
import envoy
import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import logging

pub fn main() -> Nil {
  logging.configure()
  configure_log_timestamps()
  logging.set_level(logging.Notice)

  // An unparseable or incomplete config is fatal.
  let config = case config.load() {
    Ok(config) -> config
    Error(error) -> panic as config.describe_error(error)
  }

  // In dry-run mode emails are logged rather than sent, so the API key is not
  // required.
  case config.dry_run, envoy.get("RESEND_API_KEY") {
    True, _ ->
      logging.log(
        logging.Warning,
        "Dry-run mode is enabled: emails will be logged to the console instead of being sent.",
      )
    False, Ok(_) -> Nil
    False, Error(_) -> panic as "RESEND_API_KEY environment variable not set."
  }

  let assert Ok(_) = start_supervisor()
  process.sleep_forever()
}

/// Prefix every log line with a timestamp.
@external(erlang, "ciele_ffi", "configure_timestamps")
fn configure_log_timestamps() -> Nil

fn start_supervisor() {
  supervisor.new(supervisor.OneForOne)
  |> supervisor.add(supervision.worker(server.start))
  |> supervisor.start
}
