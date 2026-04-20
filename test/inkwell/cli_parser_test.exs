defmodule Inkwell.CLIParserTest do
  use ExUnit.Case, async: true

  test "parse_mode returns :daemon with theme for daemon args" do
    assert {:daemon, %{theme: "light"}} ==
             Inkwell.CLI.parse_mode(["daemon", "--theme", "light"])
  end

  test "parse_mode returns :client usage for no args" do
    assert {:client, %{command: :usage}} == Inkwell.CLI.parse_mode([])
  end

  test "parse_mode returns :client invalid for unrecognized args" do
    # Three-or-more positionals are never a real command — the daemon should
    # exit non-zero (handled by run_client_command(%{command: :invalid})).
    assert {:client, %{command: :invalid}} == Inkwell.CLI.parse_mode(["foo", "bar", "baz"])
  end

  test "parse_mode returns :client preview (deprecated) with nil theme when --theme is omitted" do
    assert {:client, %{command: :preview, file: "file.md", theme: nil, deprecated: true}} ==
             Inkwell.CLI.parse_mode(["preview", "file.md"])
  end

  test "parse_mode returns :client preview (deprecated) with theme" do
    assert {:client, %{command: :preview, file: "file.md", theme: "light", deprecated: true}} ==
             Inkwell.CLI.parse_mode(["preview", "file.md", "--theme", "light"])
  end

  test "parse_mode returns :client for stop command" do
    assert {:client, %{command: :stop}} == Inkwell.CLI.parse_mode(["stop"])
  end

  test "parse_mode returns :client for status command" do
    assert {:client, %{command: :status}} == Inkwell.CLI.parse_mode(["status"])
  end

  test "parse_mode returns :client browse with theme" do
    assert {:client, %{command: :browse, dir: ".", theme: "light"}} ==
             Inkwell.CLI.parse_mode([".", "--theme", "light"])
  end

  describe "parse_mode [path] routing" do
    setup do
      root = Path.join(System.tmp_dir!(), "inkwell-parse-#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    test "routes an existing file to :preview", %{root: root} do
      file = Path.join(root, "note.md")
      File.write!(file, "# hi")

      assert {:client, %{command: :preview, file: ^file, theme: nil}} =
               Inkwell.CLI.parse_mode([file])
    end

    test "routes an existing directory to :browse", %{root: root} do
      assert {:client, %{command: :browse, dir: ^root, theme: nil}} =
               Inkwell.CLI.parse_mode([root])
    end

    test "routes a missing path to :path_not_found", %{root: root} do
      missing = Path.join(root, "nope")

      assert {:client, %{command: :path_not_found, path: ^missing}} =
               Inkwell.CLI.parse_mode([missing])
    end

    test "follows symlink to file → :preview", %{root: root} do
      target = Path.join(root, "real.md")
      link = Path.join(root, "link.md")
      File.write!(target, "# hi")
      :ok = File.ln_s(target, link)

      assert {:client, %{command: :preview, file: ^link, theme: nil}} =
               Inkwell.CLI.parse_mode([link])
    end

    test "follows symlink to dir → :browse", %{root: root} do
      target = Path.join(root, "realdir")
      link = Path.join(root, "linkdir")
      File.mkdir_p!(target)
      :ok = File.ln_s(target, link)

      assert {:client, %{command: :browse, dir: ^link, theme: nil}} =
               Inkwell.CLI.parse_mode([link])
    end

    test "threads --theme through to :preview", %{root: root} do
      file = Path.join(root, "note.md")
      File.write!(file, "# hi")

      assert {:client, %{command: :preview, file: ^file, theme: "light"}} =
               Inkwell.CLI.parse_mode([file, "--theme", "light"])
    end

    test "threads --theme through to :browse", %{root: root} do
      assert {:client, %{command: :browse, dir: ^root, theme: "light"}} =
               Inkwell.CLI.parse_mode([root, "--theme", "light"])
    end
  end

  describe "classify_path/1" do
    setup do
      root =
        Path.join(System.tmp_dir!(), "inkwell-classify-#{System.unique_integer([:positive])}")

      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    test "returns :file for a regular file", %{root: root} do
      path = Path.join(root, "note.md")
      File.write!(path, "# hi")
      assert Inkwell.CLI.classify_path(path) == :file
    end

    test "returns :directory for a directory", %{root: root} do
      assert Inkwell.CLI.classify_path(root) == :directory
    end

    test "returns :not_found for a missing path", %{root: root} do
      assert Inkwell.CLI.classify_path(Path.join(root, "missing")) == :not_found
    end

    test "follows symlink → file", %{root: root} do
      target = Path.join(root, "real.md")
      link = Path.join(root, "link.md")
      File.write!(target, "# hi")
      :ok = File.ln_s(target, link)
      assert Inkwell.CLI.classify_path(link) == :file
    end

    test "follows symlink → directory", %{root: root} do
      target = Path.join(root, "realdir")
      link = Path.join(root, "linkdir")
      File.mkdir_p!(target)
      :ok = File.ln_s(target, link)
      assert Inkwell.CLI.classify_path(link) == :directory
    end

    test "returns :not_found for a broken symlink", %{root: root} do
      link = Path.join(root, "broken")
      :ok = File.ln_s(Path.join(root, "does-not-exist"), link)
      assert Inkwell.CLI.classify_path(link) == :not_found
    end

    test "normalizes paths with .. segments", %{root: root} do
      File.write!(Path.join(root, "hello.md"), "# hi")
      # Path.expand/1 collapses the ".." — proves classify_path goes through it.
      assert Inkwell.CLI.classify_path(Path.join([root, "sub", "..", "hello.md"])) ==
               :file
    end
  end
end
