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

  # Tests for parse_mode — verifying --help and --version flag handling

  test "parse_mode returns help command for --help flag" do
    assert {:client, %{command: :help}} = Inkwell.Application.parse_mode(["--help"])
  end

  test "parse_mode returns help command for -h flag" do
    assert {:client, %{command: :help}} = Inkwell.Application.parse_mode(["-h"])
  end

  test "parse_mode returns version command for --version flag" do
    assert {:client, %{command: :version}} = Inkwell.Application.parse_mode(["--version"])
  end

  test "parse_mode returns version command for -v flag" do
    assert {:client, %{command: :version}} = Inkwell.Application.parse_mode(["-v"])
  end

  test "parse_mode returns usage command for no args" do
    assert {:client, %{command: :usage}} = Inkwell.Application.parse_mode([])
  end

  # Tests for help_text and version_string — pure functions that don't call System.halt

  test "help_text returns usage documentation" do
    text = Inkwell.CLI.help_text()
    assert text =~ "inkwell"
    assert text =~ "<path>"
    assert text =~ "--help"
    assert text =~ "--version"
    assert text =~ "--theme"
    refute text =~ "preview"
  end

  test "version_string returns app name and version" do
    version = Inkwell.CLI.version_string()
    assert version =~ "inkwell"
    assert version =~ ~r/\d+\.\d+\.\d+/
  end

  # Tests for wait_for_server — ensures HTTP server is accepting connections

  test "wait_for_server succeeds when server is listening" do
    # Start a TCP listener on an ephemeral port
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listener)
    on_exit(fn -> :gen_tcp.close(listener) end)

    assert :ok = Inkwell.CLI.wait_for_server("http://localhost:#{port}/some/path")
  end

  test "wait_for_server returns error when no server is listening" do
    # Use a port that's definitely not listening
    assert {:error, :timeout} =
             Inkwell.CLI.wait_for_server("http://localhost:1/nope", retries: 2, delay: 10)
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

  describe "open_target/1" do
    test "returns :browser when desktop app check returns false" do
      assert Inkwell.CLI.open_target(fn -> false end) == :browser
    end

    test "returns :desktop when desktop app check returns true" do
      assert Inkwell.CLI.open_target(fn -> true end) == :desktop
    end
  end

  describe "deep_link_url/1" do
    test "builds inkwell:// URL from absolute path" do
      url = Inkwell.CLI.deep_link_url("/Users/test/notes.md")
      assert url == "inkwell://open?path=%2FUsers%2Ftest%2Fnotes.md"
    end

    test "encodes special characters in path" do
      url = Inkwell.CLI.deep_link_url("/Users/test/my notes/file.md")
      assert url =~ "inkwell://open?path="
      assert url =~ "my+notes"
    end
  end

  describe "open_file/3" do
    test "calls deep link opener when desktop app detected" do
      test_pid = self()

      opener = fn url ->
        send(test_pid, {:opened, url})
        {"", 0}
      end

      Inkwell.CLI.open_file("http://localhost:4000/?path=/test.md", "/test.md",
        check_fn: fn -> true end,
        open_fn: opener
      )

      assert_received {:opened, "inkwell://open?path=%2Ftest.md"}
    end

    test "falls back to browser URL when no desktop app" do
      test_pid = self()

      opener = fn url ->
        send(test_pid, {:opened, url})
        {"", 0}
      end

      Inkwell.CLI.open_file("http://localhost:4000/?path=/test.md", "/test.md",
        check_fn: fn -> false end,
        open_fn: opener
      )

      assert_received {:opened, "http://localhost:4000/?path=/test.md"}
    end
  end

  describe "preview_with_deprecation_notice/2" do
    test "writes deprecation notice to stderr when :deprecated is true" do
      tmp = Path.join(System.tmp_dir!(), "test-#{System.unique_integer([:positive])}.md")
      File.write!(tmp, "# hi")
      on_exit(fn -> File.rm(tmp) end)

      start_fn = fn _opts -> {:error, :test_stub} end

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Inkwell.CLI.preview_with_deprecation_notice(
            %{file: tmp, theme: nil, deprecated: true},
            start_fn
          )
        end)

      assert stderr =~ "'preview' is deprecated"
      assert stderr =~ "use 'inkwell <file>' instead"
    end

    test "does NOT write deprecation notice when :deprecated is absent" do
      tmp = Path.join(System.tmp_dir!(), "test-#{System.unique_integer([:positive])}.md")
      File.write!(tmp, "# hi")
      on_exit(fn -> File.rm(tmp) end)

      start_fn = fn _opts -> {:error, :test_stub} end

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Inkwell.CLI.preview_with_deprecation_notice(
            %{file: tmp, theme: nil},
            start_fn
          )
        end)

      refute stderr =~ "deprecated"
    end
  end

  describe "format_path_not_found/1" do
    test "formats a clear error message for the given path" do
      assert Inkwell.CLI.format_path_not_found("/nope") ==
               "Error: no such file or directory: /nope"
    end
  end
end
