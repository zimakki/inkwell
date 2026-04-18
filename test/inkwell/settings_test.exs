defmodule Inkwell.SettingsTest do
  use ExUnit.Case, async: false

  @theme_path Path.join(System.user_home!(), ".inkwell/theme")

  setup do
    backup = if File.exists?(@theme_path), do: File.read!(@theme_path)
    File.rm(@theme_path)

    on_exit(fn ->
      if backup, do: File.write!(@theme_path, backup), else: File.rm(@theme_path)
    end)

    :ok
  end

  test "read_theme/0 returns nil when no file exists" do
    refute File.exists?(@theme_path)
    assert Inkwell.Settings.read_theme() == nil
  end

  test "write_theme + read_theme roundtrip for valid themes" do
    Inkwell.Settings.write_theme("light")
    assert Inkwell.Settings.read_theme() == "light"

    Inkwell.Settings.write_theme("dark")
    assert Inkwell.Settings.read_theme() == "dark"
  end

  test "read_theme/0 returns nil when file contents are invalid" do
    File.mkdir_p!(Path.dirname(@theme_path))
    File.write!(@theme_path, "purple")
    assert Inkwell.Settings.read_theme() == nil
  end

  test "read_theme/0 trims whitespace" do
    File.mkdir_p!(Path.dirname(@theme_path))
    File.write!(@theme_path, "  dark\n")
    assert Inkwell.Settings.read_theme() == "dark"
  end

  test "write_theme/1 raises on invalid theme" do
    assert_raise FunctionClauseError, fn -> Inkwell.Settings.write_theme("purple") end
  end
end
