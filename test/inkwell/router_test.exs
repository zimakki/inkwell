defmodule Inkwell.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test

  setup do
    Inkwell.History.reset()
    :persistent_term.put(:inkwell_theme, "dark")

    base = Path.join(System.tmp_dir!(), "inkwell-router-#{System.unique_integer([:positive])}")
    File.mkdir_p!(base)
    test_file = Path.join(base, "test.md")
    File.write!(test_file, "# Test\n\nHello world")

    on_exit(fn -> File.rm_rf!(base) end)

    {:ok, %{test_file: test_file, base: base}}
  end

  test "GET /health returns 200 with ok: true" do
    conn = conn(:get, "/health") |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"ok" => true}
  end

  test "GET /status returns daemon info" do
    conn = conn(:get, "/status") |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["running"] == true
  end

  test "GET / with valid file returns HTML", %{test_file: test_file} do
    conn =
      conn(:get, "/?path=#{URI.encode_www_form(test_file)}")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    assert conn.resp_body =~ "Test"
    assert conn.resp_body =~ "Hello world"
  end

  test "GET / with missing file returns 404" do
    conn =
      conn(:get, "/?path=#{URI.encode_www_form("/nonexistent/file.md")}")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 404
  end

  test "GET / without path or dir returns 200 with picker page" do
    conn = conn(:get, "/") |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    assert conn.resp_body =~ "data-no-file"
    assert conn.resp_body =~ "app.js"
  end

  test "GET / with dir param returns browse page HTML", %{base: base} do
    conn =
      conn(:get, "/?dir=#{URI.encode_www_form(base)}")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    assert conn.resp_body =~ "data-browse-dir=\"#{base}\""
    assert conn.resp_body =~ "app.js"
  end

  test "GET /open with valid file returns JSON with url", %{test_file: test_file} do
    conn =
      conn(:get, "/open?path=#{URI.encode_www_form(test_file)}&theme=dark")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert is_binary(body["url"])
  end

  test "GET /open with .markdown file returns 200", %{base: base} do
    md_file = Path.join(base, "readme.markdown")
    File.write!(md_file, "# Markdown Extension Test")

    conn =
      conn(:get, "/open?path=#{URI.encode_www_form(md_file)}&theme=dark")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert is_binary(body["url"])
  end

  test "GET /open without path returns 400" do
    conn =
      conn(:get, "/open?theme=dark")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 400
  end

  test "GET /open with non-md file returns 400" do
    conn =
      conn(:get, "/open?path=/tmp/file.txt&theme=dark")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 400
  end

  test "GET /search returns results", %{test_file: test_file} do
    Inkwell.History.push(test_file)

    conn =
      conn(:get, "/search?current=#{URI.encode_www_form(test_file)}&q=")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    results = Jason.decode!(conn.resp_body)
    assert is_map(results)
    assert is_list(results["recent"])
    assert is_list(results["siblings"])
  end

  test "GET /search without current returns recent files only", %{test_file: test_file} do
    Inkwell.History.push(test_file)

    conn =
      conn(:get, "/search?q=")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert is_map(body)
    assert is_list(body["recent"])
    assert body["siblings"] == []
    assert body["repository"] == nil
  end

  test "GET /search with current returns structured response", %{test_file: test_file} do
    Inkwell.History.push(test_file)

    conn =
      conn(:get, "/search?current=#{URI.encode_www_form(test_file)}&q=")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert is_map(body)
    assert is_list(body["recent"])
    assert is_list(body["siblings"])
  end

  test "GET /toggle-theme toggles between dark and light" do
    :persistent_term.put(:inkwell_theme, "dark")

    conn = conn(:get, "/toggle-theme") |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["theme"] == "light"
    assert :persistent_term.get(:inkwell_theme) == "light"
  end

  test "unknown route returns 404" do
    conn = conn(:get, "/nonexistent") |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 404
  end

  # ── Browse routes ──

  test "GET /browse returns markdown files in directory", %{base: base, test_file: test_file} do
    conn =
      conn(:get, "/browse?dir=#{URI.encode_www_form(base)}")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    results = Jason.decode!(conn.resp_body)
    assert is_list(results)
    paths = Enum.map(results, & &1["path"])
    assert test_file in paths
  end

  test "GET /browse with query filters results", %{base: base} do
    other = Path.join(base, "other.md")
    File.write!(other, "# Other\n\nbody")

    conn =
      conn(:get, "/browse?dir=#{URI.encode_www_form(base)}&q=other")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    results = Jason.decode!(conn.resp_body)
    assert length(results) == 1
    assert hd(results)["filename"] == "other.md"
  end

  test "GET /browse without dir returns 400" do
    conn =
      conn(:get, "/browse")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 400
  end

  test "GET /switch with source=browse bypasses allowed_path?", %{base: base} do
    # Create a file in a different directory (not sibling, not in history)
    other_dir =
      Path.join(System.tmp_dir!(), "inkwell-browse-#{System.unique_integer([:positive])}")

    File.mkdir_p!(other_dir)
    other_file = Path.join(other_dir, "browsed.md")
    File.write!(other_file, "# Browsed\n\nbody")
    on_exit(fn -> File.rm_rf!(other_dir) end)

    current = Path.join(base, "test.md")

    conn =
      conn(
        :get,
        "/switch?current=#{URI.encode_www_form(current)}&path=#{URI.encode_www_form(other_file)}&source=browse"
      )
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["path"] == other_file
    assert body["filename"] == "browsed.md"
  end

  test "GET /switch with source=browse still validates .md extension", %{base: base} do
    txt_file = Path.join(base, "gamma.txt")
    File.write!(txt_file, "text")
    current = Path.join(base, "test.md")

    conn =
      conn(
        :get,
        "/switch?current=#{URI.encode_www_form(current)}&path=#{URI.encode_www_form(txt_file)}&source=browse"
      )
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 403
  end

  test "GET /switch with source=browse validates file exists", %{base: base} do
    current = Path.join(base, "test.md")

    conn =
      conn(
        :get,
        "/switch?current=#{URI.encode_www_form(current)}&path=#{URI.encode_www_form("/nonexistent/file.md")}&source=browse"
      )
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 403
  end

  test "GET /switch with source=repository allows files under git root", %{base: base} do
    sub_dir = Path.join(base, "sub")
    File.mkdir_p!(sub_dir)
    File.mkdir_p!(Path.join(base, ".git"))
    sub_file = Path.join(sub_dir, "deep.md")
    File.write!(sub_file, "# Deep File")
    current = Path.join(base, "test.md")

    conn =
      conn(
        :get,
        "/switch?current=#{URI.encode_www_form(current)}&path=#{URI.encode_www_form(sub_file)}&source=repository"
      )
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["path"] == sub_file
  end

  test "GET /preview with source=browse bypasses allowed_path?", %{base: base} do
    other_dir =
      Path.join(System.tmp_dir!(), "inkwell-browse-#{System.unique_integer([:positive])}")

    File.mkdir_p!(other_dir)
    other_file = Path.join(other_dir, "preview-test.md")
    File.write!(other_file, "# Preview Test\n\ncontent here")
    on_exit(fn -> File.rm_rf!(other_dir) end)

    current = Path.join(base, "test.md")

    conn =
      conn(
        :get,
        "/preview?current=#{URI.encode_www_form(current)}&path=#{URI.encode_www_form(other_file)}&source=browse"
      )
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 200
    assert conn.resp_body =~ "Preview Test"
  end
end
