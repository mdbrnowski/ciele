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
  matching one of the `ignore_selectors` (CSS selectors), strip every attribute
  named in `ignore_attributes` from the remaining tags, and pretty-print the
  result.

  Returns `{:ok, html}` for a parseable document with a body, or `{:error, nil}`
  otherwise (so the caller can fall back to comparing the raw content).
  """
  def comparable_content(content, ignore_selectors, ignore_attributes) do
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
              |> drop_attributes(ignore_attributes)
              |> Floki.raw_html(pretty: true)

            {:ok, html}
        end

      {:error, _reason} ->
        {:error, nil}
    end
  rescue
    _ -> {:error, nil}
  end

  defp drop_attributes(tree, []), do: tree

  defp drop_attributes(tree, names) do
    # Floki lowercases attribute names when parsing, and HTML treats them
    # case-insensitively.
    names = Enum.map(names, &String.downcase/1)

    Floki.traverse_and_update(tree, fn
      {tag, attrs, children} when is_binary(tag) ->
        {tag, Enum.reject(attrs, fn {name, _} -> name in names end), children}

      other ->
        other
    end)
  end
end
