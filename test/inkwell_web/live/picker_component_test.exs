defmodule InkwellWeb.PickerComponentTest do
  use InkwellWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  @tmp_dir System.tmp_dir!()
           |> Path.join("inkwell_picker_test_#{System.unique_integer([:positive])}")

  setup do
    File.mkdir_p!(@tmp_dir)
    foo = Path.join(@tmp_dir, "foo.md")
    bar = Path.join(@tmp_dir, "bar.md")
    File.write!(foo, "# Foo")
    File.write!(bar, "# Bar")

    on_exit(fn -> File.rm_rf!(@tmp_dir) end)

    {:ok, foo: foo, bar: bar}
  end

  test "picker hidden initially, opens via search button click", %{conn: conn, foo: foo} do
    {:ok, view, html} = live(conn, ~p"/files?#{[path: foo]}")
    refute html =~ ~s|id="picker-overlay" class="open"|

    view |> element("#btn-search") |> render_click()
    assert has_element?(view, "#picker-overlay.open")
  end

  test "picker filters results as user types", %{conn: conn, foo: foo} do
    {:ok, view, _html} = live(conn, ~p"/files?#{[path: foo]}")
    view |> element("#btn-search") |> render_click()

    html =
      view
      |> form("#picker-search-form", %{"q" => "bar"})
      |> render_change()

    assert html =~ "bar.md"
  end

  test "selecting a result navigates to /files?path=...", %{conn: conn, foo: foo} do
    {:ok, view, _} = live(conn, ~p"/files?#{[path: foo]}")
    view |> element("#btn-search") |> render_click()

    view |> element(".picker-item", "bar.md") |> render_click()

    {target, _flash} = assert_redirect(view, 200)
    assert target =~ "/files"
    assert target =~ "bar.md"
  end
end
