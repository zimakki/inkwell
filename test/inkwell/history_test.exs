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
end
