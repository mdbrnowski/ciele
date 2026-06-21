defmodule Ciele.Html do
  @moduledoc """
  HTML normalization for ciele's change detection, backed by Floki.

  Called from Gleam (`ciele/server`) via Erlang FFI as `Elixir.Ciele.Html`.
  The `{:ok, _}` / `{:error, nil}` shape maps onto Gleam's
  `Result(String, Nil)`.
  """

  @doc """
  Reduce `content` to the part worth comparing: parse it as an HTML document,
  keep only the `<body>`, drop every `<script>`, and pretty-print the result.

  Returns `{:ok, html}` for a parseable document with a body, or `{:error, nil}`
  when there is no body or the content is not parseable HTML (so the caller can
  fall back to comparing the raw content).
  """
  def comparable_content(content) do
    Application.ensure_all_started(:floki)

    case Floki.parse_document(content) do
      {:ok, document} ->
        case Floki.find(document, "body") do
          [] ->
            {:error, nil}

          body ->
            html =
              body
              |> Floki.filter_out("script")
              |> Floki.raw_html(pretty: true)

            {:ok, html}
        end

      {:error, _reason} ->
        {:error, nil}
    end
  rescue
    _ -> {:error, nil}
  end
end
