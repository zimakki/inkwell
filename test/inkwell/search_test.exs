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
    results = Inkwell.Search.search(current, "")

    assert Enum.any?(results, &(&1.path == current and &1.section == :recent))
    assert Enum.any?(results, &(&1.path == sibling and &1.section == :sibling))
  end

  test "search excludes non-markdown files", %{current: current, base: base} do
    results = Inkwell.Search.search(current, "")
    gamma_txt = Path.join(base, "gamma.txt")
    refute Enum.any?(results, &(&1.path == gamma_txt))
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
    results = Inkwell.Search.search(current, "beta")
    assert Enum.any?(results, &(&1.filename == "beta.md"))
  end

  test "allowed_path? accepts sibling files", %{current: current, sibling: sibling} do
    assert Inkwell.Search.allowed_path?(current, sibling) == true
  end

  test "allowed_path? rejects files outside allowed set", %{current: current} do
    assert Inkwell.Search.allowed_path?(current, "/etc/passwd") == false
  end
end
