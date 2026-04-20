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
    assert html =~ ~r/<h2[^>]*>H2<\/h2>/
    assert html =~ ~r/<h3[^>]*>H3<\/h3>/
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

  test "sanitizer strips script tags from markdown" do
    :persistent_term.put(:inkwell_theme, "dark")

    html = Inkwell.Renderer.render(~s|# Title\n\n<script>alert("xss")</script>\n|)

    assert html =~ "<h1>Title</h1>"
    refute html =~ "<script"
    refute html =~ "alert("
  end

  test "sanitizer strips iframe tags from markdown" do
    :persistent_term.put(:inkwell_theme, "dark")

    html = Inkwell.Renderer.render(~s|<iframe src="https://evil.example"></iframe>\n|)

    refute html =~ "<iframe"
  end

  test "sanitizer strips javascript: URLs from links" do
    :persistent_term.put(:inkwell_theme, "dark")

    html = Inkwell.Renderer.render(~s|[Click](javascript:alert(1))\n|)

    refute html =~ "javascript:"
  end

  test "mermaid block survives sanitization and unusual surrounding fences" do
    :persistent_term.put(:inkwell_theme, "dark")

    html =
      Inkwell.Renderer.render("""
      Some intro.

      ```bash
      echo "this is bash, not mermaid"
      ```

      ```mermaid
      graph TD;
      A-->B;
      ```

      And then more.
      """)

    assert html =~ ~s(<pre class="mermaid">)
    assert html =~ "graph TD;"
    assert html =~ "echo"
  end

  test "escapes HTML inside mermaid blocks" do
    :persistent_term.put(:inkwell_theme, "dark")

    html = Inkwell.Renderer.render("```mermaid\nA-->B[\"<script>alert(1)</script>\"]\n```\n")

    assert html =~ "<pre class=\"mermaid\">"
    refute html =~ "<script>alert"
  end

  # ── render_with_nav/1 ──────────────────────────

  test "render_with_nav returns {html, headings, alerts} tuple" do
    :persistent_term.put(:inkwell_theme, "dark")

    {html, headings, alerts} =
      Inkwell.Renderer.render_with_nav("## Section\n\n> [!WARNING]\n> Be careful\n")

    assert is_binary(html)
    assert [%{level: 2, text: "Section", id: "section"}] = headings
    assert [%{type: "warning"}] = alerts
  end

  test "render_with_nav injects heading IDs into HTML" do
    :persistent_term.put(:inkwell_theme, "dark")

    {html, _headings, _alerts} = Inkwell.Renderer.render_with_nav("## My Section\n")

    assert html =~ ~s(id="my-section")
  end

  test "render_with_nav with empty input returns empty nav data" do
    :persistent_term.put(:inkwell_theme, "dark")

    {html, headings, alerts} = Inkwell.Renderer.render_with_nav("")

    assert is_binary(html)
    assert headings == []
    assert alerts == []
  end
end
