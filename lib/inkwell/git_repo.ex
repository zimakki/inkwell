defmodule Inkwell.GitRepo do
  @moduledoc "Detects git repositories and discovers markdown files within them."

  @skip_dirs MapSet.new([
               ".git",
               "node_modules",
               "_build",
               "deps",
               ".elixir_ls",
               "_opam",
               "target",
               "vendor",
               ".cache",
               "dist",
               "build"
             ])

  @doc "Walk up from `path` looking for a `.git` directory. Returns `{:ok, root}` or `:error`."
  def find_root(path) do
    path
    |> Path.expand()
    |> do_find_root()
  end

  defp do_find_root("/"), do: :error

  defp do_find_root(dir) do
    dir = if File.dir?(dir), do: dir, else: Path.dirname(dir)

    if File.exists?(Path.join(dir, ".git")) do
      {:ok, dir}
    else
      do_find_root(Path.dirname(dir))
    end
  end

  @doc "Recursively find all `.md` files under `root`, skipping common artifact directories."
  def find_markdown_files(root) do
    root
    |> walk_dir([])
    |> Enum.sort()
  end

  defp walk_dir(dir, acc) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.reduce(entries, acc, fn entry, acc ->
          full = Path.join(dir, entry)

          cond do
            File.dir?(full) and entry not in @skip_dirs ->
              walk_dir(full, acc)

            String.ends_with?(entry, ".md") ->
              [full | acc]

            true ->
              acc
          end
        end)

      {:error, _} ->
        acc
    end
  end
end
