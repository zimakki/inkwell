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

  @doc "Render markdown to {html, headings, alerts} with injected IDs for navigation."
  def render_with_nav(markdown) do
    theme = :persistent_term.get(:inkwell_theme, "dark")
    syntax_theme = if theme == "light", do: "onelight", else: "onedark"

    opts =
      Keyword.put(@base_opts, :syntax_highlight, formatter: {:html_inline, [theme: syntax_theme]})

    html =
      markdown
      |> MDEx.parse_document!(opts)
      |> MDEx.traverse_and_update(&swap_mermaid/1)
      |> MDEx.to_html!(opts)

    Inkwell.DocNav.process(markdown, html)
  end

  defp swap_mermaid(%MDEx.CodeBlock{info: "mermaid", literal: code}) do
    %MDEx.HtmlBlock{
      literal: ~s|<pre class="mermaid">#{Plug.HTML.html_escape(code)}</pre>|
    }
  end

  defp swap_mermaid(node), do: node
end
