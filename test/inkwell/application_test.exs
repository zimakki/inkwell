defmodule Inkwell.ApplicationTest do
  use ExUnit.Case, async: true

  test "parse_mode returns :daemon with theme for daemon args" do
    assert {:daemon, %{theme: "light"}} ==
             Inkwell.Application.parse_mode(["daemon", "--theme", "light"])
  end

  test "parse_mode returns :daemon with default theme for no args" do
    assert {:daemon, %{theme: "dark"}} == Inkwell.Application.parse_mode([])
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

  test "parse_mode returns :client for unknown command (usage)" do
    assert {:client, %{command: :usage}} == Inkwell.Application.parse_mode(["unknown"])
  end
end
