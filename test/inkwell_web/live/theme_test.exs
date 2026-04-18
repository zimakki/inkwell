defmodule InkwellWeb.ThemeTest do
  use InkwellWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    :persistent_term.put(:inkwell_theme, "dark")
    :ok
  end

  test "clicking toggle flips persistent_term and broadcasts", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert render(view) =~ ~s|data-theme="dark"|

    Phoenix.PubSub.subscribe(Inkwell.PubSub, "theme")
    view |> element("#btn-toggle-theme") |> render_click()

    assert_receive {:theme_changed, "light"}, 500
    assert :persistent_term.get(:inkwell_theme) == "light"
    assert render(view) =~ ~s|data-theme="light"|
  end

  test "second session receives theme change broadcast", %{conn: conn} do
    {:ok, view1, _} = live(build_conn(), ~p"/")
    {:ok, view2, _} = live(conn, ~p"/")

    view1 |> element("#btn-toggle-theme") |> render_click()

    # Tiny delay for the broadcast to propagate to view2
    Process.sleep(50)
    assert render(view2) =~ ~s|data-theme="light"|
  end
end
