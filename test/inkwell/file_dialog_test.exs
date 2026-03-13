defmodule Inkwell.FileDialogTest do
  use ExUnit.Case, async: true

  import Inkwell.FileDialog, only: [parse_osascript_result: 2]

  describe "parse_osascript_result/2" do
    test "parses a successful file pick with POSIX path" do
      output = "/Users/someone/docs/readme.md\n"
      assert parse_osascript_result(output, 0) == {:ok, "/Users/someone/docs/readme.md"}
    end

    test "parses a successful directory pick" do
      output = "/Users/someone/docs/\n"
      assert parse_osascript_result(output, 0) == {:ok, "/Users/someone/docs/"}
    end

    test "returns :cancel on user cancelled (exit code 1 with cancel message)" do
      output = "execution error: User canceled. (-128)\n"
      assert parse_osascript_result(output, 1) == :cancel
    end

    test "returns :cancel on exit code 1 with canceled text" do
      output = "User canceled.\n"
      assert parse_osascript_result(output, 1) == :cancel
    end

    test "returns error on non-zero exit with other error" do
      output = "some unexpected error\n"
      assert parse_osascript_result(output, 1) == {:error, "some unexpected error"}
    end

    test "returns error on exit code 0 with empty output" do
      assert parse_osascript_result("", 0) == {:error, "empty response"}
      assert parse_osascript_result("\n", 0) == {:error, "empty response"}
    end
  end
end
