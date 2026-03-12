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

    {:ok, %{current: current, sibling: sibling}}
  end

  test "extract_title reads the first h1", %{current: current} do
    assert Inkwell.Search.extract_title(current) == "Alpha Title"
  end

  test "search returns recent and sibling markdown files", %{current: current, sibling: sibling} do
    results = Inkwell.Search.search(current, "")

    assert Enum.any?(results, &(&1.path == current and &1.section == :recent))
    assert Enum.any?(results, &(&1.path == sibling and &1.section == :sibling))
  end

  test "fuzzy score prefers early consecutive matches" do
    assert Inkwell.Search.fuzzy_score("alp", "alpha") >
             Inkwell.Search.fuzzy_score("alp", "example")
  end
end
