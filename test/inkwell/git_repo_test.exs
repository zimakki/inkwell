defmodule Inkwell.GitRepoTest do
  use ExUnit.Case, async: true

  describe "find_root/1" do
    test "finds git root from a file inside a repo" do
      file = Path.expand("lib/inkwell/git_repo.ex")
      assert {:ok, root} = Inkwell.GitRepo.find_root(file)
      assert File.exists?(Path.join(root, ".git"))
    end

    test "finds git root from a directory inside a repo" do
      dir = Path.expand("lib/inkwell")
      assert {:ok, root} = Inkwell.GitRepo.find_root(dir)
      assert File.exists?(Path.join(root, ".git"))
    end

    test "returns :error for path outside any repo" do
      assert :error = Inkwell.GitRepo.find_root("/tmp")
    end

    test "returns :error for root directory" do
      assert :error = Inkwell.GitRepo.find_root("/")
    end
  end

  describe "find_markdown_files/1" do
    setup do
      base = Path.join(System.tmp_dir!(), "inkwell-gitrepo-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(base, ".git"))
      File.mkdir_p!(Path.join(base, "docs/api"))
      File.mkdir_p!(Path.join(base, "node_modules/pkg"))
      File.mkdir_p!(Path.join(base, "_build/dev"))
      File.mkdir_p!(Path.join(base, ".superpowers"))

      File.write!(Path.join(base, "README.md"), "# Root Readme")
      File.write!(Path.join(base, "docs/setup.md"), "# Setup")
      File.write!(Path.join(base, "docs/api/endpoints.md"), "# Endpoints")
      File.write!(Path.join(base, "node_modules/pkg/README.md"), "# Should skip")
      File.write!(Path.join(base, "_build/dev/notes.md"), "# Should skip")
      File.write!(Path.join(base, ".superpowers/design.md"), "# Should NOT skip")
      File.write!(Path.join(base, "not_markdown.txt"), "ignore")

      on_exit(fn -> File.rm_rf!(base) end)
      {:ok, %{base: base}}
    end

    test "finds all .md files recursively", %{base: base} do
      files = Inkwell.GitRepo.find_markdown_files(base)
      filenames = Enum.map(files, &Path.basename/1)

      assert "README.md" in filenames
      assert "setup.md" in filenames
      assert "endpoints.md" in filenames
      assert "design.md" in filenames
    end

    test "skips directories in the skip list", %{base: base} do
      files = Inkwell.GitRepo.find_markdown_files(base)
      paths = Enum.join(files, " ")

      refute paths =~ "node_modules"
      refute paths =~ "_build"
    end

    test "does NOT skip .superpowers", %{base: base} do
      files = Inkwell.GitRepo.find_markdown_files(base)
      assert Enum.any?(files, &String.contains?(&1, ".superpowers"))
    end

    test "excludes non-markdown files", %{base: base} do
      files = Inkwell.GitRepo.find_markdown_files(base)
      refute Enum.any?(files, &String.ends_with?(&1, ".txt"))
    end

    test "returns sorted paths", %{base: base} do
      files = Inkwell.GitRepo.find_markdown_files(base)
      assert files == Enum.sort(files)
    end
  end
end
