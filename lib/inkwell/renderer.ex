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
    render: [unsafe: true]
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

    md =
      Regex.replace(~r/```mermaid\n(.*?)```/s, markdown, fn _, content ->
        escaped = Plug.HTML.html_escape(content)
        "<pre class=\"mermaid\">#{escaped}</pre>"
      end)

    html = MDEx.to_html!(md, opts)
    Inkwell.DocNav.process(markdown, html)
  end
end
