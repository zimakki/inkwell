defmodule Inkwell.Renderer do
  @moduledoc "Converts markdown to HTML with syntax highlighting and mermaid support."

  @base_opts [
    extension: [
      strikethrough: true,
      table: true,
      autolink: true,
      tasklist: true,
      footnotes: true,
      alerts: true
    ],
    render: [unsafe: true],
    sanitize:
      MDEx.Document.default_sanitize_options()
      |> Keyword.update(:add_generic_attributes, ["class", "id"], fn existing ->
        Enum.uniq(existing ++ ["class", "id"])
      end)
  ]

  @doc "Render markdown to HTML string (legacy, no nav data)."
  def render(markdown) do
    {html, _headings, _alerts} = render_with_nav(markdown)
    html
  end

  @doc """
  Render markdown to {html, headings, alerts} with injected IDs for navigation.

  Options:
    * `:base_dir` — when given, relative image URLs are resolved against this
      directory and rewritten to `/raw?path=<abs>`, so the browser can fetch
      them through the daemon's raw-file endpoint.
  """
  def render_with_nav(markdown, opts \\ []) do
    theme = :persistent_term.get(:inkwell_theme, "dark")
    syntax_theme = if theme == "light", do: "onelight", else: "onedark"
    base_dir = Keyword.get(opts, :base_dir)

    mdex_opts =
      Keyword.put(@base_opts, :syntax_highlight, formatter: {:html_inline, [theme: syntax_theme]})

    html =
      markdown
      |> MDEx.parse_document!(mdex_opts)
      |> MDEx.traverse_and_update(&swap_mermaid/1)
      |> MDEx.traverse_and_update(&rewrite_image_url(&1, base_dir))
      |> MDEx.to_html!(mdex_opts)

    Inkwell.DocNav.process(markdown, html)
  end

  defp swap_mermaid(%MDEx.CodeBlock{info: "mermaid", literal: code}) do
    %MDEx.HtmlBlock{
      literal: ~s|<pre class="mermaid">#{Plug.HTML.html_escape(code)}</pre>|
    }
  end

  defp swap_mermaid(node), do: node

  defp rewrite_image_url(%MDEx.Image{url: url} = img, base_dir)
       when is_binary(base_dir) do
    if relative_image?(url) do
      expanded = Path.expand(url, base_dir)
      %{img | url: "/raw?" <> URI.encode_query(path: expanded)}
    else
      img
    end
  end

  defp rewrite_image_url(node, _base_dir), do: node

  defp relative_image?(url) do
    not String.starts_with?(url, ["http://", "https://", "data:", "file://", "/", "mailto:"])
  end
end
