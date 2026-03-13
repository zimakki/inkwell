defmodule Inkwell.GitRepo do
  @moduledoc "Detects git repositories and discovers markdown files within them."

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
end
