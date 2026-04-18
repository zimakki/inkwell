defmodule InkwellWeb.BrowseLiveTest do
  use InkwellWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  @fixtures_dir Path.expand("../../fixtures", __DIR__)

  test "GET /browse?dir=X lists markdown files in the directory", %{conn: conn} do
    File.mkdir_p!(@fixtures_dir)
    File.write!(Path.join(@fixtures_dir, "alpha.md"), "# Alpha")
    File.write!(Path.join(@fixtures_dir, "beta.md"), "# Beta")

    on_exit(fn ->
      File.rm_rf!(Path.join(@fixtures_dir, "alpha.md"))
      File.rm_rf!(Path.join(@fixtures_dir, "beta.md"))
    end)

    {:ok, view, _html} = live(conn, ~p"/browse?#{[dir: @fixtures_dir]}")

    assert render(view) =~ "alpha.md"
    assert render(view) =~ "beta.md"
  end

  test "GET /browse without dir param redirects to /", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/browse")
  end
end
