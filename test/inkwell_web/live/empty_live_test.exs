defmodule InkwellWeb.EmptyLiveTest do
  use InkwellWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "GET / auto-opens the file picker", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Inkwell"
    refute html =~ "Open a file to get started"
    assert has_element?(view, "#picker-overlay.open")
  end

  test "GET / exposes theme toggle and search buttons", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "button#btn-toggle-theme")
    assert has_element?(view, "button#btn-search")
  end
end
