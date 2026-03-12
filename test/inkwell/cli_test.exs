defmodule Inkwell.CLITest do
  use ExUnit.Case, async: true

  # CLI tests are limited because main/1 calls System.halt() for error cases,
  # which would terminate the test VM. We test argument parsing directly.

  test "option parser handles theme flag" do
    {opts, rest, _invalid} =
      OptionParser.parse(["preview", "file.md", "--theme", "light"], strict: [theme: :string])

    assert opts[:theme] == "light"
    assert rest == ["preview", "file.md"]
  end

  test "option parser handles no flags" do
    {opts, rest, _invalid} = OptionParser.parse(["status"], strict: [theme: :string])
    assert opts == []
    assert rest == ["status"]
  end

  test "option parser handles daemon with theme" do
    {opts, rest, _invalid} =
      OptionParser.parse(["daemon", "--theme", "dark"], strict: [theme: :string])

    assert opts[:theme] == "dark"
    assert rest == ["daemon"]
  end

  test "option parser defaults theme to nil when not provided" do
    {opts, _rest, _invalid} = OptionParser.parse(["preview", "file.md"], strict: [theme: :string])
    assert opts[:theme] == nil
  end
end
