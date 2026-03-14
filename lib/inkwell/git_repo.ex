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

  # Cache TTL — results stay fresh for 30 seconds
  @cache_ttl_ms 30_000
  @cache_table :inkwell_git_repo_cache

  @doc "Ensure the ETS cache table exists. Called from Application.start/2."
  def init_cache do
    :ets.new(@cache_table, [:set, :public, :named_table])
  rescue
    ArgumentError -> :ok
  end

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

  @doc "Recursively find all `.md` files under `root`, skipping common artifact directories. Results are cached for #{@cache_ttl_ms}ms."
  def find_markdown_files(root) do
    now = System.monotonic_time(:millisecond)

    case cache_lookup(root) do
      {:ok, files, cached_at} when now - cached_at < @cache_ttl_ms ->
        files

      stale ->
        # Use a lock key to prevent concurrent walks.
        # If another process is already walking, return stale data (or wait).
        lock_key = {:walking, root}

        case :ets.insert_new(@cache_table, {lock_key, true}) do
          true ->
            # We got the lock — do the walk
            try do
              files =
                root
                |> walk_dir([])
                |> Enum.sort()

              cache_put(root, files, now)
              files
            after
              :ets.delete(@cache_table, lock_key)
            end

          false ->
            # Another process is walking — return stale data if available
            case stale do
              {:ok, files, _cached_at} -> files
              :miss -> do_wait_for_cache(root, now, 50)
            end
        end
    end
  rescue
    ArgumentError ->
      # ETS table doesn't exist (e.g. in tests without init_cache)
      root |> walk_dir([]) |> Enum.sort()
  end

  # Wait briefly for another process to populate the cache (cold start only)
  defp do_wait_for_cache(_root, _now, 0), do: []

  defp do_wait_for_cache(root, now, retries) do
    Process.sleep(100)

    case cache_lookup(root) do
      {:ok, files, cached_at} when now - cached_at < @cache_ttl_ms -> files
      _ -> do_wait_for_cache(root, now, retries - 1)
    end
  end

  defp cache_lookup(root) do
    case :ets.lookup(@cache_table, root) do
      [{^root, files, cached_at}] -> {:ok, files, cached_at}
      [] -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp cache_put(root, files, now) do
    :ets.insert(@cache_table, {root, files, now})
  rescue
    ArgumentError -> :ok
  end

  defp walk_dir(dir, acc) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.reduce(entries, acc, fn entry, acc ->
          cond do
            MapSet.member?(@skip_dirs, entry) ->
              acc

            String.ends_with?(entry, ".md") ->
              [Path.join(dir, entry) | acc]

            true ->
              full = Path.join(dir, entry)
              if File.dir?(full), do: walk_dir(full, acc), else: acc
          end
        end)

      {:error, _} ->
        acc
    end
  end
end
