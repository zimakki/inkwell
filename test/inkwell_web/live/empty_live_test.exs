defmodule InkwellWeb.EmptyLiveTest do
  use InkwellWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "GET / renders empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Open a file to get started"
    assert html =~ "Inkwell"
  end

  test "GET / exposes theme toggle and search buttons", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "button#btn-toggle-theme")
    assert has_element?(view, "button#btn-search")
  end
end
