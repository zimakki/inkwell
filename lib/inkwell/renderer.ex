defmodule Inkwell.Renderer do
  @moduledoc "Converts markdown to HTML with syntax highlighting and mermaid support."

  @base_opts [
    extension: [
      strikethrough: true,
      table: true,
      autolink: true,
      tasklist: true,
      footnotes: true
    ],
    render: [unsafe: true]
  ]

  def render(markdown) do
    theme = :persistent_term.get(:inkwell_theme, "dark")
    syntax_theme = if theme == "light", do: "onelight", else: "onedark"

    opts =
      Keyword.put(@base_opts, :syntax_highlight, formatter: {:html_inline, [theme: syntax_theme]})

    md =
      Regex.replace(~r/```mermaid\n(.*?)```/s, markdown, fn _, content ->
        escaped = Plug.HTML.html_escape(content)
        "<pre class=\"mermaid\">#{escaped}</pre>"
      end)

    MDEx.to_html!(md, opts)
  end
end
