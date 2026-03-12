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

  test "renders multiple heading levels" do
    :persistent_term.put(:inkwell_theme, "dark")

    html = Inkwell.Renderer.render("# H1\n## H2\n### H3\n")

    assert html =~ "<h1>H1</h1>"
    assert html =~ "<h2>H2</h2>"
    assert html =~ "<h3>H3</h3>"
  end

  test "renders code blocks with syntax highlighting" do
    :persistent_term.put(:inkwell_theme, "dark")

    html = Inkwell.Renderer.render("```elixir\nIO.puts(\"hello\")\n```\n")

    assert html =~ "IO"
    assert html =~ "hello"
  end

  test "renders empty input without error" do
    :persistent_term.put(:inkwell_theme, "dark")

    html = Inkwell.Renderer.render("")
    assert is_binary(html)
  end

  test "uses light theme syntax highlighting" do
    :persistent_term.put(:inkwell_theme, "light")

    html = Inkwell.Renderer.render("```elixir\n:ok\n```\n")

    assert is_binary(html)
  end

  test "passes through raw HTML when unsafe mode is enabled" do
    :persistent_term.put(:inkwell_theme, "dark")

    html = Inkwell.Renderer.render("<div class=\"custom\">content</div>\n")

    assert html =~ "<div class=\"custom\">content</div>"
  end

  test "escapes HTML inside mermaid blocks" do
    :persistent_term.put(:inkwell_theme, "dark")

    html = Inkwell.Renderer.render("```mermaid\nA-->B[\"<script>alert(1)</script>\"]\n```\n")

    assert html =~ "<pre class=\"mermaid\">"
    refute html =~ "<script>alert"
  end
end
