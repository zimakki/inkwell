defmodule Inkwell.ApplicationTest do
  use ExUnit.Case, async: true

  test "parse_mode returns :daemon with theme for daemon args" do
    assert {:daemon, %{theme: "light"}} ==
             Inkwell.Application.parse_mode(["daemon", "--theme", "light"])
  end

  test "parse_mode returns :client usage for no args" do
    assert {:client, %{command: :usage}} == Inkwell.Application.parse_mode([])
  end

  test "parse_mode returns :client for preview command" do
    assert {:client, %{command: :preview, file: "file.md", theme: "dark"}} ==
             Inkwell.Application.parse_mode(["preview", "file.md"])
  end

  test "parse_mode returns :client for preview with theme" do
    assert {:client, %{command: :preview, file: "file.md", theme: "light"}} ==
             Inkwell.Application.parse_mode(["preview", "file.md", "--theme", "light"])
  end

  test "parse_mode returns :client for stop command" do
    assert {:client, %{command: :stop}} == Inkwell.Application.parse_mode(["stop"])
  end

  test "parse_mode returns :client for status command" do
    assert {:client, %{command: :status}} == Inkwell.Application.parse_mode(["status"])
  end

  test "parse_mode returns :client browse for unknown single arg (treated as dir)" do
    assert {:client, %{command: :browse, dir: "unknown", theme: "dark"}} ==
             Inkwell.Application.parse_mode(["unknown"])
  end

  test "parse_mode returns :client browse for dot argument" do
    assert {:client, %{command: :browse, dir: ".", theme: "dark"}} ==
             Inkwell.Application.parse_mode(["."])
  end

  test "parse_mode returns :client browse for directory path" do
    assert {:client, %{command: :browse, dir: "/tmp/docs", theme: "dark"}} ==
             Inkwell.Application.parse_mode(["/tmp/docs"])
  end

  test "parse_mode returns :client browse with theme" do
    assert {:client, %{command: :browse, dir: ".", theme: "light"}} ==
             Inkwell.Application.parse_mode([".", "--theme", "light"])
  end
end
