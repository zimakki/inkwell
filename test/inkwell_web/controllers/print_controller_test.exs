defmodule InkwellWeb.PrintControllerTest do
  use InkwellWeb.ConnCase, async: true

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "print_controller_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "GET /print" do
    test "renders the article HTML in a minimal page", %{conn: conn, tmp: tmp} do
      md = Path.join(tmp, "doc.md")
      File.write!(md, "# Hello\n\n## Section A\n\nbody text\n")

      conn = get(conn, ~p"/print?path=#{md}")

      html = response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
      assert html =~ "Hello"
      assert html =~ "Section A"
      assert html =~ "body text"
      # Print-only assets, no app shell.
      assert html =~ "/print.css"
      refute html =~ "/app.css"
      refute html =~ "/assets/app.js"
    end

    test "returns 404 when the file does not exist", %{conn: conn, tmp: tmp} do
      missing = Path.join(tmp, "nope.md")
      conn = get(conn, ~p"/print?path=#{missing}")
      assert response(conn, 404)
    end

    test "returns 400 when the path param is missing", %{conn: conn} do
      conn = get(conn, ~p"/print")
      assert response(conn, 400)
    end

    test "renders a TOC page when toc=true (default)", %{conn: conn, tmp: tmp} do
      md = Path.join(tmp, "doc.md")
      File.write!(md, "# Title\n\n## Alpha\n\n## Bravo\n\n")
      conn = get(conn, ~p"/print?path=#{md}")
      html = response(conn, 200)

      assert html =~ "id=\"toc-page\""
      assert html =~ ">Alpha<"
      assert html =~ ">Bravo<"
    end

    test "skips the TOC page when toc=false", %{conn: conn, tmp: tmp} do
      md = Path.join(tmp, "doc.md")
      File.write!(md, "# Title\n\n## Alpha\n\n")
      conn = get(conn, ~p"/print?path=#{md}&toc=false")
      html = response(conn, 200)
      refute html =~ "id=\"toc-page\""
    end

    test "emits @page rule reflecting the pagesize param", %{conn: conn, tmp: tmp} do
      md = Path.join(tmp, "doc.md")
      File.write!(md, "# Hi\n")
      conn = get(conn, ~p"/print?path=#{md}&pagesize=letter&margins=narrow")
      html = response(conn, 200)
      assert html =~ "size: letter"
      assert html =~ "margin: 0.5in"
    end

    test "emits page-numbers @page rule when numbers=true", %{conn: conn, tmp: tmp} do
      md = Path.join(tmp, "doc.md")
      File.write!(md, "# Hi\n")
      conn = get(conn, ~p"/print?path=#{md}&numbers=true")
      html = response(conn, 200)
      assert html =~ "@bottom-center"
      assert html =~ "counter(page)"
    end

    test "inlines autoprint script when autoprint=1", %{conn: conn, tmp: tmp} do
      md = Path.join(tmp, "doc.md")
      File.write!(md, "# Hi\n")
      conn = get(conn, ~p"/print?path=#{md}&autoprint=1")
      html = response(conn, 200)
      assert html =~ "window.print()"
      assert html =~ "addEventListener('load'"
    end
  end
end
