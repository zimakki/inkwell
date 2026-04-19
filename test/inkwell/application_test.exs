defmodule Inkwell.ApplicationTest do
  use ExUnit.Case, async: true

  test "parse_mode returns :daemon with theme for daemon args" do
    assert {:daemon, %{theme: "light"}} ==
             Inkwell.Application.parse_mode(["daemon", "--theme", "light"])
  end

  test "parse_mode returns :client usage for no args" do
    assert {:client, %{command: :usage}} == Inkwell.Application.parse_mode([])
  end

  test "parse_mode returns :client preview with nil theme when --theme is omitted" do
    assert {:client, %{command: :preview, file: "file.md", theme: nil}} ==
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
    assert {:client, %{command: :browse, dir: "unknown", theme: nil}} ==
             Inkwell.Application.parse_mode(["unknown"])
  end

  test "parse_mode returns :client browse for dot argument" do
    assert {:client, %{command: :browse, dir: ".", theme: nil}} ==
             Inkwell.Application.parse_mode(["."])
  end

  test "parse_mode returns :client browse for directory path" do
    assert {:client, %{command: :browse, dir: "/tmp/docs", theme: nil}} ==
             Inkwell.Application.parse_mode(["/tmp/docs"])
  end

  test "parse_mode returns :client browse with theme" do
    assert {:client, %{command: :browse, dir: ".", theme: "light"}} ==
             Inkwell.Application.parse_mode([".", "--theme", "light"])
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
      assert Inkwell.Application.classify_path(path) == :file
    end

    test "returns :directory for a directory", %{root: root} do
      assert Inkwell.Application.classify_path(root) == :directory
    end

    test "returns :not_found for a missing path", %{root: root} do
      assert Inkwell.Application.classify_path(Path.join(root, "missing")) == :not_found
    end

    test "follows symlink → file", %{root: root} do
      target = Path.join(root, "real.md")
      link = Path.join(root, "link.md")
      File.write!(target, "# hi")
      :ok = File.ln_s(target, link)
      assert Inkwell.Application.classify_path(link) == :file
    end

    test "follows symlink → directory", %{root: root} do
      target = Path.join(root, "realdir")
      link = Path.join(root, "linkdir")
      File.mkdir_p!(target)
      :ok = File.ln_s(target, link)
      assert Inkwell.Application.classify_path(link) == :directory
    end

    test "returns :not_found for a broken symlink", %{root: root} do
      link = Path.join(root, "broken")
      :ok = File.ln_s(Path.join(root, "does-not-exist"), link)
      assert Inkwell.Application.classify_path(link) == :not_found
    end

    test "normalizes paths with .. segments", %{root: root} do
      File.write!(Path.join(root, "hello.md"), "# hi")
      # Path.expand/1 collapses the ".." — proves classify_path goes through it.
      assert Inkwell.Application.classify_path(Path.join([root, "sub", "..", "hello.md"])) ==
               :file
    end
  end
end
