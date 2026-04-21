defmodule Inkwell.Search do
  @moduledoc """
  Indexes markdown files by filename and H1 title.
  Provides fuzzy search across both fields.
  """

  require Logger

  @max_results 50
  @max_repo_initial 20

  def extract_title(path) do
    cache_key = {:title, path}

    case :ets.lookup(:inkwell_git_repo_cache, cache_key) do
      [{^cache_key, title}] ->
        title

      [] ->
        title = do_extract_title(path)
        :ets.insert(:inkwell_git_repo_cache, {cache_key, title})
        title
    end
  rescue
    ArgumentError -> do_extract_title(path)
  end

  @doc "Drops the cached H1 title for `path`. Call when the file changes."
  def invalidate_title(path) do
    :ets.delete(:inkwell_git_repo_cache, {:title, path})
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp do_extract_title(path) do
    path
    |> File.stream!()
    |> Stream.take(15)
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^#\s+(.+)$/, String.trim_trailing(line)) do
        [_, title] -> String.trim(title)
        nil -> nil
      end
    end)
  rescue
    _e in [File.Error, IO.StreamError] -> nil
  end

  def fuzzy_score("", _candidate), do: 0
  def fuzzy_score(_query, nil), do: 0
  def fuzzy_score(_query, ""), do: 0

  def fuzzy_score(query, candidate) do
    q_chars = query |> String.downcase() |> normalize_separators() |> String.graphemes()
    c_chars = candidate |> String.downcase() |> normalize_separators() |> String.graphemes()

    case do_match(q_chars, c_chars, 0, 0, 0, nil, false) do
      nil ->
        0

      {matched, consec_bonus, first_pos} ->
        position_bonus = max(0, 2 - first_pos)
        matched + consec_bonus + position_bonus
    end
  end

  def list_recent do
    {t_recent, recent} =
      :timer.tc(fn ->
        Inkwell.Library.list_recent!()
        |> Enum.map(& &1.path)
        |> Enum.filter(&File.exists?/1)
        |> Enum.map(fn path ->
          %{
            path: path,
            filename: Path.basename(path),
            title: extract_title(path),
            section: :recent,
            active: false
          }
        end)
      end)

    Logger.info(
      "[search] list_recent: recent entries=#{length(recent)} took #{t_recent / 1000}ms"
    )

    # Try to derive repository from most recent file
    recent_paths = MapSet.new(recent, & &1.path)

    {t_repo, repository} =
      :timer.tc(fn ->
        case List.first(recent) do
          %{path: path} -> build_repository(path, recent_paths)
          nil -> nil
        end
      end)

    Logger.info("[search] list_recent: build_repository took #{t_repo / 1000}ms")

    %{recent: recent, siblings: [], repository: repository}
  end

  def list_files(current_path) do
    t_start = System.monotonic_time(:millisecond)
    dir = Path.dirname(current_path)
    recent = Inkwell.Library.list_recent!() |> Enum.map(& &1.path)
    existing_recent = Enum.filter(recent, &File.exists?/1)

    recent_entries =
      Enum.map(existing_recent, fn path ->
        %{
          path: path,
          filename: Path.basename(path),
          title: extract_title(path),
          section: :recent,
          active: path == current_path
        }
      end)

    t_recent = System.monotonic_time(:millisecond)

    recent_paths = MapSet.new(existing_recent)

    sibling_entries =
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.map(&Path.join(dir, &1))
      |> Enum.reject(&MapSet.member?(recent_paths, &1))
      |> Enum.sort()
      |> Enum.map(fn path ->
        %{
          path: path,
          filename: Path.basename(path),
          title: extract_title(path),
          section: :sibling,
          active: path == current_path
        }
      end)

    t_siblings = System.monotonic_time(:millisecond)

    known_paths = MapSet.union(recent_paths, MapSet.new(sibling_entries, & &1.path))
    repository = build_repository(current_path, known_paths)

    t_repo = System.monotonic_time(:millisecond)

    Logger.info(
      "[search] list_files: recent=#{t_recent - t_start}ms siblings=#{t_siblings - t_recent}ms repo=#{t_repo - t_siblings}ms total=#{t_repo - t_start}ms"
    )

    %{recent: recent_entries, siblings: sibling_entries, repository: repository}
  end

  def search(current_path, query) when query in ["", nil], do: list_files(current_path)

  def search(current_path, query) do
    %{recent: recent, siblings: siblings, repository: repo} = list_files(current_path)

    all_entries = recent ++ siblings ++ if(repo, do: repo.files, else: [])

    scored =
      all_entries
      |> Enum.map(fn entry ->
        filename_score = fuzzy_score(query, entry.filename)
        title_score = fuzzy_score(query, entry.title) * 1.2
        rel_path_score = fuzzy_score(query, Map.get(entry, :rel_path)) * 0.8
        score = Enum.max([filename_score, title_score, rel_path_score])
        {entry, score}
      end)
      |> Enum.reject(fn {_entry, score} -> score == 0 end)
      |> Enum.sort_by(fn {_entry, score} -> score end, :desc)
      |> Enum.take(@max_results)

    # Re-group into sections
    {recent_results, rest} = Enum.split_with(scored, fn {e, _} -> e.section == :recent end)

    {sibling_results, repo_results} =
      Enum.split_with(rest, fn {e, _} -> e.section == :sibling end)

    strip = fn list -> Enum.map(list, fn {entry, _score} -> entry end) end

    repo_section =
      if repo do
        %{repo | files: strip.(repo_results)}
      else
        nil
      end

    %{recent: strip.(recent_results), siblings: strip.(sibling_results), repository: repo_section}
  end

  def list_directory_files(dir_path) do
    if File.exists?(Path.join(dir_path, ".git")) do
      # Git repo root — discover all markdown files recursively
      {t_walk, paths} = :timer.tc(fn -> Inkwell.GitRepo.find_markdown_files(dir_path) end)

      {t_titles, entries} =
        :timer.tc(fn ->
          Enum.map(paths, fn path ->
            rel = Path.relative_to(path, dir_path)

            %{
              path: path,
              filename: Path.basename(path),
              rel_path: rel,
              title: extract_title(path),
              section: :browse,
              active: false
            }
          end)
        end)

      Logger.info(
        "[search] list_directory_files(git): walk=#{t_walk / 1000}ms (#{length(paths)} files) titles=#{t_titles / 1000}ms"
      )

      entries
    else
      case File.ls(dir_path) do
        {:ok, entries} ->
          entries
          |> Enum.filter(&String.ends_with?(&1, ".md"))
          |> Enum.sort()
          |> Enum.map(fn filename ->
            path = Path.join(dir_path, filename)

            %{
              path: path,
              filename: filename,
              title: extract_title(path),
              section: :browse,
              active: false
            }
          end)

        {:error, _} ->
          []
      end
    end
  end

  def browse(dir_path, query) do
    files = search_directory(dir_path, query)
    %{recent: recent} = list_recent()
    %{recent: recent, siblings: files, repository: nil}
  end

  def search_directory(dir_path, query) when query in ["", nil] do
    list_directory_files(dir_path)
  end

  def search_directory(dir_path, query) do
    list_directory_files(dir_path)
    |> Enum.map(fn entry ->
      filename_score = fuzzy_score(query, entry.filename)
      title_score = fuzzy_score(query, entry.title) * 1.2
      rel_path_score = fuzzy_score(query, Map.get(entry, :rel_path)) * 0.8
      score = Enum.max([filename_score, title_score, rel_path_score])
      {entry, score}
    end)
    |> Enum.reject(fn {_entry, score} -> score == 0 end)
    |> Enum.sort_by(fn {_entry, score} -> score end, :desc)
    |> Enum.take(@max_results)
    |> Enum.map(fn {entry, _score} -> entry end)
  end

  def allowed_path?(current_path, candidate_path) do
    dir = Path.dirname(current_path)

    recent_paths =
      Inkwell.Library.list_recent!() |> Enum.map(& &1.path) |> Enum.filter(&File.exists?/1)

    sibling_paths =
      case File.ls(dir) do
        {:ok, entries} ->
          entries
          |> Enum.filter(&String.ends_with?(&1, ".md"))
          |> Enum.map(&Path.join(dir, &1))

        {:error, _} ->
          []
      end

    candidate_path in recent_paths or candidate_path in sibling_paths
  end

  defp build_repository(current_path, known_paths) do
    case Inkwell.GitRepo.find_root(current_path) do
      {:ok, root} ->
        {t_walk, all_files} = :timer.tc(fn -> Inkwell.GitRepo.find_markdown_files(root) end)
        repo_name = Path.basename(root)

        repo_only = Enum.reject(all_files, &MapSet.member?(known_paths, &1))

        {t_titles, repo_files} =
          :timer.tc(fn ->
            repo_only
            |> Enum.take(@max_repo_initial)
            |> Enum.map(fn path ->
              rel = Path.relative_to(path, root)

              %{
                path: path,
                filename: Path.basename(path),
                rel_path: rel,
                title: extract_title(path),
                section: :repository
              }
            end)
          end)

        Logger.info(
          "[search] build_repository: walk=#{t_walk / 1000}ms (#{length(all_files)} files) titles=#{t_titles / 1000}ms (#{length(repo_files)} entries) root=#{root}"
        )

        %{name: repo_name, files: repo_files, total: length(repo_only)}

      :error ->
        nil
    end
  end

  defp do_match([], _c, matched, cb, _idx, fp, _prev), do: {matched, cb, fp || 0}
  defp do_match(_q, [], _m, _cb, _idx, _fp, _prev), do: nil

  defp do_match([q | qr], [c | cr], matched, cb, idx, fp, prev) when q == c do
    new_fp = fp || idx
    new_cb = if prev, do: cb + 3, else: cb
    do_match(qr, cr, matched + 1, new_cb, idx + 1, new_fp, true)
  end

  defp do_match(q, [_c | cr], matched, cb, idx, fp, _prev) do
    do_match(q, cr, matched, cb, idx + 1, fp, false)
  end

  defp normalize_separators(str) do
    String.replace(str, ~r/[_\-]/, " ")
  end
end
