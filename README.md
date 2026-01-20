# ciele

An application that monitors selected static websites and notifies you of any changes on them.

The name comes from a Polish idiom: *[patrzeć jak cielę na malowane wrota](https://pl.wiktionary.org/wiki/patrze%C4%87_jak_ciel%C4%99_na_malowane_wrota)*, which refers to how this app works.

## Configuration

To use the app, you need to set the `RESEND_API_KEY` environment variable. You can obtain the API key from [resend.com](https://resend.com).
In addition, you need to create a configuration file at `config/config.yaml`:

```yaml
email_address: yourmail@gmail.com
sender_email_address: ciele@yourdomain.com
domains:
  - www.erlang.org
  - www.rabbitmq.com
```

## Running the app

To run the app, use

```bash
rebar3 shell
```

To run it in the background, you can use `run_erl`:

```bash
mkdir -p pipes logs
run_erl -daemon ./pipes/ ./logs "rebar3 shell"
```

<img src="assets/ciele.png" width="300">
