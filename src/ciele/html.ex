defmodule Ciele.Html do
  @moduledoc """
  HTML normalization for ciele's change detection, backed by Floki.

  Called from Gleam (`ciele/server`) via Erlang FFI as `Elixir.Ciele.Html`.
  The `{:ok, _}` / `{:error, nil}` shape maps onto Gleam's
  `Result(String, Nil)`.
  """

  @doc """
  Reduce `content` to the part worth comparing: parse it as an HTML document,
  keep only the `<body>`, drop every `<script>` as well as every element
  matching one of the `ignore_selectors` (CSS selectors), and pretty-print the
  result. When `ignore_classes` is true, `class` attributes are also stripped
  from every remaining tag.

  Returns `{:ok, html}` for a parseable document with a body, or `{:error, nil}`
  otherwise (so the caller can fall back to comparing the raw content).
  """
  def comparable_content(content, ignore_selectors, ignore_classes) do
    Application.ensure_all_started(:floki)

    case Floki.parse_document(content) do
      {:ok, document} ->
        case Floki.find(document, "body") do
          [] ->
            {:error, nil}

          body ->
            selector = Enum.join(["script" | ignore_selectors], ", ")

            html =
              body
              |> Floki.filter_out(selector)
              |> maybe_drop_classes(ignore_classes)
              |> Floki.raw_html(pretty: true)

            {:ok, html}
        end

      {:error, _reason} ->
        {:error, nil}
    end
  rescue
    _ -> {:error, nil}
  end

  defp maybe_drop_classes(tree, false), do: tree

  defp maybe_drop_classes(tree, true) do
    Floki.traverse_and_update(tree, fn
      {tag, attrs, children} ->
        {tag, Enum.reject(attrs, fn {name, _} -> name == "class" end), children}

      other ->
        other
    end)
  end
end
