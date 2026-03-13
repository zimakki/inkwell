defmodule Inkwell.SearchTest do
  use ExUnit.Case, async: false

  setup do
    Inkwell.History.reset()

    base = Path.join(System.tmp_dir!(), "inkwell-search-#{System.unique_integer([:positive])}")
    File.mkdir_p!(base)

    current = Path.join(base, "alpha.md")
    sibling = Path.join(base, "beta.md")
    other = Path.join(base, "gamma.txt")

    File.write!(current, "# Alpha Title\n\nbody")
    File.write!(sibling, "# Beta Heading\n\nbody")
    File.write!(other, "ignore")

    Inkwell.History.push(current)

    on_exit(fn -> File.rm_rf!(base) end)

    {:ok, %{base: base, current: current, sibling: sibling}}
  end

  test "extract_title reads the first h1", %{current: current} do
    assert Inkwell.Search.extract_title(current) == "Alpha Title"
  end

  test "extract_title returns nil when no h1 exists", %{base: base} do
    no_h1 = Path.join(base, "no_heading.md")
    File.write!(no_h1, "Just some text\nNo heading here")
    assert Inkwell.Search.extract_title(no_h1) == nil
  end

  test "extract_title returns nil for non-existent file" do
    assert Inkwell.Search.extract_title("/nonexistent/file.md") == nil
  end

  test "search returns recent and sibling markdown files", %{current: current, sibling: sibling} do
    result = Inkwell.Search.search(current, "")

    assert Enum.any?(result.recent, &(&1.path == current and &1.section == :recent))
    assert Enum.any?(result.siblings, &(&1.path == sibling and &1.section == :sibling))
  end

  test "search excludes non-markdown files", %{current: current, base: base} do
    result = Inkwell.Search.search(current, "")
    gamma_txt = Path.join(base, "gamma.txt")
    all_paths = Enum.map(result.recent ++ result.siblings, & &1.path)
    refute gamma_txt in all_paths
  end

  test "fuzzy score prefers early consecutive matches" do
    assert Inkwell.Search.fuzzy_score("alp", "alpha") >
             Inkwell.Search.fuzzy_score("alp", "example")
  end

  test "fuzzy score returns 0 for empty query" do
    assert Inkwell.Search.fuzzy_score("", "anything") == 0
  end

  test "fuzzy score returns 0 for nil candidate" do
    assert Inkwell.Search.fuzzy_score("query", nil) == 0
  end

  test "fuzzy score returns 0 for empty candidate" do
    assert Inkwell.Search.fuzzy_score("query", "") == 0
  end

  test "fuzzy score returns 0 when no characters match" do
    assert Inkwell.Search.fuzzy_score("xyz", "abc") == 0
  end

  test "search with query filters results", %{current: current} do
    result = Inkwell.Search.search(current, "beta")

    all_files =
      result.recent ++
        result.siblings ++ if(result.repository, do: result.repository.files, else: [])

    assert Enum.any?(all_files, &(&1.filename == "beta.md"))
  end

  test "allowed_path? accepts sibling files", %{current: current, sibling: sibling} do
    assert Inkwell.Search.allowed_path?(current, sibling) == true
  end

  test "allowed_path? rejects files outside allowed set", %{current: current} do
    assert Inkwell.Search.allowed_path?(current, "/etc/passwd") == false
  end

  describe "list_recent/0" do
    test "returns structured response with only recent files", %{current: current} do
      result = Inkwell.Search.list_recent()
      assert is_map(result)
      assert is_list(result.recent)
      assert result.siblings == []
      assert result.repository == nil
      assert Enum.any?(result.recent, &(&1.path == current))
    end
  end

  describe "structured list_files/1" do
    test "returns map with recent and siblings keys", %{current: current, sibling: sibling} do
      result = Inkwell.Search.list_files(current)
      assert is_map(result)
      assert Enum.any?(result.recent, &(&1.path == current))
      assert Enum.any?(result.siblings, &(&1.path == sibling))
    end
  end

  describe "structured search/2" do
    test "search with query returns structured result", %{current: current} do
      result = Inkwell.Search.search(current, "beta")
      assert is_map(result)

      all_files =
        result.recent ++
          result.siblings ++
          ((result.repository && result.repository.files) || [])

      assert Enum.any?(all_files, &(&1.filename == "beta.md"))
    end
  end

  describe "list_directory_files/1" do
    test "lists markdown files in a directory", %{base: base, current: current, sibling: sibling} do
      results = Inkwell.Search.list_directory_files(base)

      paths = Enum.map(results, & &1.path)
      assert current in paths
      assert sibling in paths
      assert Enum.all?(results, &(&1.section == :browse))
    end

    test "excludes non-markdown files", %{base: base} do
      results = Inkwell.Search.list_directory_files(base)
      filenames = Enum.map(results, & &1.filename)
      refute "gamma.txt" in filenames
    end

    test "extracts titles", %{base: base} do
      results = Inkwell.Search.list_directory_files(base)
      alpha = Enum.find(results, &(&1.filename == "alpha.md"))
      assert alpha.title == "Alpha Title"
    end

    test "returns empty list for nonexistent directory" do
      assert Inkwell.Search.list_directory_files("/nonexistent/dir") == []
    end

    test "returns empty list for inaccessible directory" do
      assert Inkwell.Search.list_directory_files("/root/nope") == []
    end
  end

  describe "search_directory/2" do
    test "returns all files with empty query", %{base: base} do
      results = Inkwell.Search.search_directory(base, "")
      assert length(results) == 2
    end

    test "filters by query", %{base: base} do
      results = Inkwell.Search.search_directory(base, "alpha")
      assert length(results) == 1
      assert hd(results).filename == "alpha.md"
    end

    test "returns empty for no matches", %{base: base} do
      results = Inkwell.Search.search_directory(base, "zzzzz")
      assert results == []
    end
  end
end
