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
end
