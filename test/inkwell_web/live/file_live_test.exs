defmodule InkwellWeb.FileLiveTest do
  use InkwellWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  @tmp_dir System.tmp_dir!() |> Path.join("inkwell_file_live_test")

  setup do
    File.mkdir_p!(@tmp_dir)
    path = Path.join(@tmp_dir, "doc.md")
    File.write!(path, "# Hello\n\nSome content.")

    on_exit(fn -> File.rm_rf!(@tmp_dir) end)

    {:ok, path: path}
  end

  test "GET /files?path=... renders the file", %{conn: conn, path: path} do
    {:ok, _view, html} = live(conn, ~p"/files?#{[path: path]}")

    assert html =~ "Hello"
    assert html =~ "Some content"
  end

  test "pushes updates when PubSub broadcasts :reload", %{conn: conn, path: path} do
    {:ok, view, _html} = live(conn, ~p"/files?#{[path: path]}")

    payload = %{
      html: "<h1>Updated</h1>",
      headings: [],
      alerts: []
    }

    Phoenix.PubSub.broadcast(
      Inkwell.PubSub,
      "file:" <> Inkwell.Watcher.resolve_path(path),
      {:reload, payload}
    )

    assert render(view) =~ "Updated"
  end

  test "missing path redirects to /", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} =
             live(conn, ~p"/files?#{[path: "/nonexistent/nope.md"]}")
  end
end
