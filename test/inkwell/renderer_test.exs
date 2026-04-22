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

  describe "GitHub-style alert blocks" do
    setup do
      :persistent_term.put(:inkwell_theme, "dark")
      :ok
    end

    test "renders note alerts with the markdown-alert-note class" do
      html = Inkwell.Renderer.render("> [!NOTE]\n> Heads up.\n")

      assert html =~ ~r/<div class="markdown-alert markdown-alert-note"[^>]*>/
      assert html =~ ~r/<p class="markdown-alert-title">Note<\/p>/
      assert html =~ "Heads up."
    end

    test "renders tip alerts" do
      html = Inkwell.Renderer.render("> [!TIP]\n> Quick tip.\n")

      assert html =~ ~r/<div class="markdown-alert markdown-alert-tip"[^>]*>/
      assert html =~ ~r/<p class="markdown-alert-title">Tip<\/p>/
    end

    test "renders important alerts" do
      html = Inkwell.Renderer.render("> [!IMPORTANT]\n> Pay attention.\n")

      assert html =~ ~r/<div class="markdown-alert markdown-alert-important"[^>]*>/
      assert html =~ ~r/<p class="markdown-alert-title">Important<\/p>/
    end

    test "renders warning alerts" do
      html = Inkwell.Renderer.render("> [!WARNING]\n> Be careful.\n")

      assert html =~ ~r/<div class="markdown-alert markdown-alert-warning"[^>]*>/
      assert html =~ ~r/<p class="markdown-alert-title">Warning<\/p>/
    end

    test "renders caution alerts" do
      html = Inkwell.Renderer.render("> [!CAUTION]\n> Do not do this.\n")

      assert html =~ ~r/<div class="markdown-alert markdown-alert-caution"[^>]*>/
      assert html =~ ~r/<p class="markdown-alert-title">Caution<\/p>/
    end
  end

  describe "image URL rewriting" do
    setup do
      :persistent_term.put(:inkwell_theme, "dark")
      :ok
    end

    test "rewrites relative image paths to /raw?path=<encoded_abs> when base_dir given" do
      {html, _, _} =
        Inkwell.Renderer.render_with_nav(
          "![pic](foo.png)\n",
          base_dir: "/tmp/notes"
        )

      assert html =~ ~s(src="/raw?path=%2Ftmp%2Fnotes%2Ffoo.png")
    end

    test "resolves parent traversal and subdirectories against base_dir" do
      {html, _, _} =
        Inkwell.Renderer.render_with_nav(
          "![a](../img/a.png)\n![b](./sub/b.png)\n",
          base_dir: "/home/user/docs"
        )

      assert html =~ ~s(src="/raw?path=%2Fhome%2Fuser%2Fimg%2Fa.png")
      assert html =~ ~s(src="/raw?path=%2Fhome%2Fuser%2Fdocs%2Fsub%2Fb.png")
    end

    test "leaves absolute http(s) and root-absolute URLs unchanged" do
      markdown = """
      ![a](https://example.com/a.png)
      ![b](http://example.com/b.png)
      ![d](/already/absolute.png)
      """

      {html, _, _} = Inkwell.Renderer.render_with_nav(markdown, base_dir: "/tmp")

      assert html =~ ~s(src="https://example.com/a.png")
      assert html =~ ~s(src="http://example.com/b.png")
      assert html =~ ~s(src="/already/absolute.png")
      refute html =~ "/raw?path="
    end

    test "does not rewrite when base_dir is not provided" do
      {html, _, _} = Inkwell.Renderer.render_with_nav("![pic](foo.png)\n")

      assert html =~ ~s(src="foo.png")
      refute html =~ "/raw?path="
    end

    test "URL-encodes spaces and reserved characters in resolved paths" do
      {html, _, _} =
        Inkwell.Renderer.render_with_nav(
          "![pic](a&b?c#d%.png)\n",
          base_dir: "/tmp/some dir"
        )

      assert html =~ ~s(src="/raw?path=%2Ftmp%2Fsome+dir%2Fa%26b%3Fc%23d%25.png")
    end
  end
end
