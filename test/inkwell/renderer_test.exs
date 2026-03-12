defmodule Inkwell.RendererTest do
  use ExUnit.Case, async: true

  test "renders markdown headings and mermaid blocks" do
    :persistent_term.put(:inkwell_theme, "dark")

    html =
      Inkwell.Renderer.render("""
      # Hello

      ```mermaid
      graph TD;
      A-->B;
      ```
      """)

    assert html =~ "<h1>Hello</h1>"
    assert html =~ "<pre class=\"mermaid\">"
    assert html =~ "graph TD;"
  end
end
