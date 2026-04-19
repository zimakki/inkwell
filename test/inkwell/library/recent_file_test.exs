defmodule Inkwell.Library.RecentFileTest do
  use Inkwell.DataCase, async: false

  alias Inkwell.Library

  describe "list_recent/0" do
    test "returns an empty list when no recents exist" do
      assert Library.list_recent!() == []
    end

    test "returns entries sorted by last_opened_at descending" do
      now = DateTime.utc_now()

      {:ok, _} =
        Inkwell.Library.RecentFile
        |> Ash.Changeset.for_create(:seed, %{
          path: "/tmp/a.md",
          last_opened_at: DateTime.add(now, -60, :second),
          open_count: 1
        })
        |> Ash.create()

      {:ok, _} =
        Inkwell.Library.RecentFile
        |> Ash.Changeset.for_create(:seed, %{
          path: "/tmp/b.md",
          last_opened_at: now,
          open_count: 1
        })
        |> Ash.create()

      paths = Library.list_recent!() |> Enum.map(& &1.path)
      assert paths == ["/tmp/b.md", "/tmp/a.md"]
    end
  end

  describe "push_recent/1" do
    test "inserts a new recent with open_count = 1 and fresh last_opened_at" do
      before = DateTime.utc_now()
      {:ok, recent} = Library.push_recent("/tmp/new.md")
      after_ = DateTime.utc_now()

      assert recent.path == "/tmp/new.md"
      assert recent.open_count == 1
      assert DateTime.compare(recent.last_opened_at, before) in [:gt, :eq]
      assert DateTime.compare(recent.last_opened_at, after_) in [:lt, :eq]
    end
  end
end
