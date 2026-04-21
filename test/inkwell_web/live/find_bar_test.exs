defmodule InkwellWeb.FindBarTest do
  use InkwellWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  @tmp_dir System.tmp_dir!() |> Path.join("inkwell_find_bar_test")

  setup do
    File.mkdir_p!(@tmp_dir)
    path = Path.join(@tmp_dir, "doc.md")
    File.write!(path, "# Hello\n\nFind me.")

    on_exit(fn -> File.rm_rf!(@tmp_dir) end)

    {:ok, path: path}
  end

  test "file view renders the find bar with FindBar hook", %{conn: conn, path: path} do
    {:ok, _view, html} = live(conn, ~p"/files?#{[path: path]}")

    assert html =~ ~s(id="find-bar")
    assert html =~ ~s(phx-hook="FindBar")
  end

  test "find bar contains input, counter, and action buttons", %{conn: conn, path: path} do
    {:ok, _view, html} = live(conn, ~p"/files?#{[path: path]}")

    assert html =~ ~s(id="find-bar-input")
    assert html =~ ~s(id="find-bar-count")
    assert html =~ ~s(data-action="prev")
    assert html =~ ~s(data-action="next")
    assert html =~ ~s(data-action="close")
  end

  test "find bar input has accessible label and placeholder", %{conn: conn, path: path} do
    {:ok, _view, html} = live(conn, ~p"/files?#{[path: path]}")

    assert html =~ ~s(aria-label="Find in document")
    assert html =~ ~s(placeholder="Find in document…")
  end

  test "page header still carries the Shortcuts hook", %{conn: conn, path: path} do
    {:ok, _view, html} = live(conn, ~p"/files?#{[path: path]}")

    assert html =~ ~s(id="page-header")
    assert html =~ ~s(phx-hook="Shortcuts")
  end
end
