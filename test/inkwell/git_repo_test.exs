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
end
