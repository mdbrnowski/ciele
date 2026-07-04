# ciele

An application that monitors selected static websites and notifies you of any changes on them.

Written in [Gleam](https://gleam.run), running on the Erlang/OTP runtime.

## Configuration

To use the app, you need to set the `RESEND_API_KEY` environment variable. You can obtain the API key from [resend.com](https://resend.com).
In addition, you need to create a configuration file at `config/config.toml` (see [`config/config.example.toml`](config/config.example.toml)):

```toml
email_address = "yourmail@gmail.com"
sender_email_address = "ciele@yourdomain.com"
domains = [
  "www.gleam.run",
  "www.erlang.org",
]
```

Each `domains` entry is either a bare URL, or a table with a `url` and an optional `ignore` list of [CSS selectors](https://hexdocs.pm/floki/Floki.html#module-selectors)
whose matching elements are stripped before comparison.
This is useful for ignoring volatile regions of a page — ad slots, timestamps, view counters — that would otherwise trigger a diff email on every check:

```toml
domains = [
  "www.gleam.run",
  { url = "www.erlang.org", ignore = ["div.community", "span.timestamp"] },
]
```

### Dry-run mode

Set `dry_run = true` in the config file to try the app without sending real emails. In this mode `RESEND_API_KEY` is not required, and instead of sending emails the app logs to the console the messages it would have sent.

```toml
dry_run = true
```

## Running the app

To run the app, use

```bash
gleam run
```

The server checks every configured domain on startup and then every six hours.
Only the `<body>` is compared, with `<script>` tags and any configured `ignore` selectors dropped. When it changes, a unified diff is emailed to you.
To run it in the background you can use any process supervisor you like (for example `systemd`, `tmux`, or `nohup gleam run &`).

## Development

```bash
gleam test    # run the test suite
gleam format  # format the code
gleam build   # type-check and compile
```

The name of this app comes from a Polish idiom: *[patrzeć jak cielę na malowane wrota](https://pl.wiktionary.org/wiki/patrze%C4%87_jak_ciel%C4%99_na_malowane_wrota)*.
