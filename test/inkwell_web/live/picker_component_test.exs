defmodule InkwellWeb.PickerComponentTest do
  use InkwellWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  defmodule DialogStub do
    def start_link, do: Agent.start_link(fn -> %{} end, name: __MODULE__)
    def put(key, value), do: Agent.update(__MODULE__, &Map.put(&1, key, value))
    def pick_file, do: Agent.get(__MODULE__, &Map.get(&1, :pick_file, :cancel))
    def pick_directory, do: Agent.get(__MODULE__, &Map.get(&1, :pick_directory, :cancel))
  end

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

  test "receiving {:picker_browse, dir} navigates to /browse?dir=...", %{conn: conn, foo: foo} do
    {:ok, view, _} = live(conn, ~p"/files?#{[path: foo]}")

    send(view.pid, {:picker_browse, "/tmp/docs"})

    {target, _flash} = assert_redirect(view, 200)
    assert target =~ "/browse"
    assert URI.decode(target) =~ "/tmp/docs"
  end

  describe "Open Folder button" do
    setup do
      {:ok, _} = DialogStub.start_link()
      prev = Application.get_env(:inkwell, :file_dialog_module)
      Application.put_env(:inkwell, :file_dialog_module, DialogStub)
      on_exit(fn -> Application.put_env(:inkwell, :file_dialog_module, prev) end)
      :ok
    end

    test "clicking Open Folder navigates to /browse?dir=... when user picks a folder",
         %{conn: conn, foo: foo} do
      DialogStub.put(:pick_directory, {:ok, "/tmp/inkwell-browse-target"})

      {:ok, view, _} = live(conn, ~p"/files?#{[path: foo]}")
      view |> element("#btn-search") |> render_click()

      view |> element(".picker-btn", "Open Folder") |> render_click()

      {target, _flash} = assert_redirect(view, 200)
      assert target =~ "/browse"
      assert URI.decode(target) =~ "/tmp/inkwell-browse-target"
    end

    test "clicking Open Folder does nothing when user cancels",
         %{conn: conn, foo: foo} do
      DialogStub.put(:pick_directory, :cancel)

      {:ok, view, _} = live(conn, ~p"/files?#{[path: foo]}")
      view |> element("#btn-search") |> render_click()

      view |> element(".picker-btn", "Open Folder") |> render_click()

      refute_redirected(view, "/browse")
      assert has_element?(view, "#picker-overlay.open")
    end
  end
end
