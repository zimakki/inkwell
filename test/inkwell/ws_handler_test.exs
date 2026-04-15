defmodule Inkwell.WsHandlerTest do
  use ExUnit.Case, async: false

  setup do
    :persistent_term.put(:inkwell_theme, "dark")

    base = Path.join(System.tmp_dir!(), "inkwell-ws-#{System.unique_integer([:positive])}")
    File.mkdir_p!(base)
    test_file = Path.join(base, "preview.md")
    File.write!(test_file, "# Hello\n\nWorld")

    on_exit(fn -> File.rm_rf!(base) end)

    {:ok, %{test_file: test_file, base: base}}
  end

  test "init pushes rendered HTML immediately on connect", %{test_file: test_file} do
    result = Inkwell.WsHandler.init(path: test_file)

    assert {:push, {:text, html}, %{path: _}} = result
    assert html =~ "Hello"
    assert html =~ "World"
  end

  test "init expands the path in state", %{test_file: test_file} do
    {:push, _, state} = Inkwell.WsHandler.init(path: test_file)

    assert state.path == Inkwell.Watcher.resolve_path(test_file)
  end

  test "init registers client in Registry", %{test_file: test_file} do
    {:push, _, state} = Inkwell.WsHandler.init(path: test_file)

    clients = Registry.lookup(Inkwell.Registry, {:ws_clients, state.path})
    assert length(clients) >= 1
  end

  test "handle_in ping responds with pong" do
    state = %{path: "/tmp/any.md"}

    assert {:push, {:text, "pong"}, ^state} =
             Inkwell.WsHandler.handle_in({"ping", []}, state)
  end

  test "handle_in unknown message returns ok" do
    state = %{path: "/tmp/any.md"}

    assert {:ok, ^state} = Inkwell.WsHandler.handle_in({"unknown", []}, state)
  end

  test "handle_info :reload pushes html to client" do
    state = %{path: "/tmp/any.md"}
    html = "<p>Updated</p>"

    assert {:push, {:text, ^html}, ^state} =
             Inkwell.WsHandler.handle_info({:reload, html}, state)
  end

  test "handle_info unknown message returns ok" do
    state = %{path: "/tmp/any.md"}

    assert {:ok, ^state} = Inkwell.WsHandler.handle_info(:unexpected, state)
  end
end
