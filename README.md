# ciele

An application that monitors selected websites and notifies you of changes on them.

The name comes from a Polish proverb: *[patrzeć jak cielę na malowane wrota](https://pl.wiktionary.org/wiki/patrze%C4%87_jak_ciel%C4%99_na_malowane_wrota)*.

<img src="assets/ciele.png" width="350">

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
