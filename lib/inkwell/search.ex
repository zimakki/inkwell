defmodule Inkwell.Search do
  @moduledoc """
  Indexes markdown files by filename and H1 title.
  Provides fuzzy search across both fields.
  """

  @max_results 50

  def extract_title(path) do
    path
    |> File.stream!()
    |> Stream.take(50)
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
    q_chars = query |> String.downcase() |> String.graphemes()
    c_chars = candidate |> String.downcase() |> String.graphemes()

    case do_match(q_chars, c_chars, 0, 0, 0, nil, false) do
      nil ->
        0

      {matched, consec_bonus, first_pos} ->
        position_bonus = max(0, 2 - first_pos)
        matched + consec_bonus + position_bonus
    end
  end

  def list_files(current_path) do
    dir = Path.dirname(current_path)
    recent = Inkwell.History.list()

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

    recent_entries ++ sibling_entries
  end

  def search(current_path, ""), do: list_files(current_path)
  def search(current_path, nil), do: list_files(current_path)

  def search(current_path, query) do
    list_files(current_path)
    |> Enum.map(fn entry ->
      filename_score = fuzzy_score(query, entry.filename)
      title_score = fuzzy_score(query, entry.title) * 1.2
      score = max(filename_score, title_score)
      {entry, score}
    end)
    |> Enum.reject(fn {_entry, score} -> score == 0 end)
    |> Enum.sort_by(fn {_entry, score} -> score end, :desc)
    |> Enum.take(@max_results)
    |> Enum.map(fn {entry, _score} -> entry end)
  end

  def list_directory_files(dir_path) do
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

  def search_directory(dir_path, query) when query in ["", nil] do
    list_directory_files(dir_path)
  end

  def search_directory(dir_path, query) do
    list_directory_files(dir_path)
    |> Enum.map(fn entry ->
      filename_score = fuzzy_score(query, entry.filename)
      title_score = fuzzy_score(query, entry.title) * 1.2
      score = max(filename_score, title_score)
      {entry, score}
    end)
    |> Enum.reject(fn {_entry, score} -> score == 0 end)
    |> Enum.sort_by(fn {_entry, score} -> score end, :desc)
    |> Enum.take(@max_results)
    |> Enum.map(fn {entry, _score} -> entry end)
  end

  def allowed_path?(current_path, candidate_path) do
    current_path
    |> list_files()
    |> Enum.any?(&(&1.path == candidate_path))
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
end
