defmodule Inkwell.HistoryTest do
  use ExUnit.Case, async: false

  setup do
    Inkwell.History.reset()
    :ok
  end

  test "push keeps most recent files unique and capped" do
    Inkwell.History.push("/tmp/a.md")
    Inkwell.History.push("/tmp/b.md")
    Inkwell.History.push("/tmp/a.md")

    assert Inkwell.History.list() == ["/tmp/a.md", "/tmp/b.md"]
  end

  test "caps history at max size" do
    for i <- 1..25 do
      Inkwell.History.push("/tmp/file_#{i}.md")
    end

    history = Inkwell.History.list()
    assert length(history) == 20
    assert hd(history) == "/tmp/file_25.md"
  end

  test "list returns empty when nothing pushed" do
    assert Inkwell.History.list() == []
  end

  test "reset clears all history" do
    Inkwell.History.push("/tmp/a.md")
    Inkwell.History.reset()
    assert Inkwell.History.list() == []
  end
end
