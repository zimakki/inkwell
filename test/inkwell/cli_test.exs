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

  # Tests for preview error handling — uses the extracted pure helper so we
  # never call System.halt() from the test process.

  test "preview returns error when file does not exist" do
    result = Inkwell.CLI.preview("/nonexistent/path/file.md", [])
    assert result == {:error, "file not found: /nonexistent/path/file.md"}
  end

  # Tests for browse (directory) command

  test "browse returns error when directory does not exist" do
    result = Inkwell.CLI.browse("/nonexistent/path/dir", [])
    assert result == {:error, "directory not found: /nonexistent/path/dir"}
  end

  test "browse returns error when path is not a directory" do
    tmp = Path.join(System.tmp_dir!(), "test-#{System.unique_integer([:positive])}.md")
    File.write!(tmp, "# hello")
    on_exit(fn -> File.rm(tmp) end)

    result = Inkwell.CLI.browse(tmp, [])
    assert result == {:error, "not a directory: #{tmp}"}
  end

  test "browse returns error with message when daemon fails to start" do
    result = Inkwell.CLI.browse(".", [], fn _opts -> {:error, :timeout} end)
    assert {:error, msg} = result
    assert msg =~ "failed to start inkwell daemon"
  end

  test "browse resolves dot to absolute path" do
    result = Inkwell.CLI.browse(".", [], fn _opts -> {:ok, 9999} end)
    assert {:ok, url} = result
    abs_dir = Path.expand(".")
    assert url =~ "dir=#{URI.encode_www_form(abs_dir)}"
  end

  test "preview returns error with message when daemon fails to start" do
    # Use a real temp file so the file-exists check passes.
    tmp = Path.join(System.tmp_dir!(), "test-#{System.unique_integer([:positive])}.md")
    File.write!(tmp, "# hello")

    on_exit(fn -> File.rm(tmp) end)

    # Daemon isn't running and can't be started (no real daemon process in tests).
    # ensure_started will return {:error, _} because the spawned process will fail
    # or time out. We stub at the daemon layer by passing a start_fn.
    result = Inkwell.CLI.preview(tmp, [], fn _opts -> {:error, :timeout} end)
    assert {:error, msg} = result
    assert msg =~ "failed to start inkwell daemon"
    assert msg =~ "timeout"
  end
end
