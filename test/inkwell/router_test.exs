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

  test "GET / without path param returns 400" do
    conn = conn(:get, "/") |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 400
  end

  test "GET /open with valid file returns JSON with url", %{test_file: test_file} do
    conn =
      conn(:get, "/open?path=#{URI.encode_www_form(test_file)}&theme=dark")
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
    assert is_list(results)
  end

  test "GET /search without current returns 400" do
    conn =
      conn(:get, "/search?q=test")
      |> Inkwell.Router.call(Inkwell.Router.init([]))

    assert conn.status == 400
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
end
