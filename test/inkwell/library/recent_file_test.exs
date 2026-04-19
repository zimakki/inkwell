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

    test "caps at 20 entries, dropping the oldest" do
      now = DateTime.utc_now()

      for i <- 1..25 do
        {:ok, _} =
          Inkwell.Library.RecentFile
          |> Ash.Changeset.for_create(:seed, %{
            path: "/tmp/f#{i}.md",
            last_opened_at: DateTime.add(now, -i, :second),
            open_count: 1
          })
          |> Ash.create()
      end

      recents = Library.list_recent!()
      assert length(recents) == 20

      paths = Enum.map(recents, & &1.path)
      # Most recent (i=1 → -1s ago) is first.
      assert List.first(paths) == "/tmp/f1.md"
      # 20th most recent is /tmp/f20.md; /tmp/f21..f25 should be dropped.
      assert List.last(paths) == "/tmp/f20.md"
      refute "/tmp/f25.md" in paths
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

    test "refreshes last_opened_at and increments open_count on existing path" do
      {:ok, first} = Library.push_recent("/tmp/repeat.md")
      assert first.open_count == 1

      # Small sleep to make the timestamp comparison meaningful.
      Process.sleep(2)

      {:ok, second} = Library.push_recent("/tmp/repeat.md")
      assert second.id == first.id
      assert second.open_count == 2
      assert DateTime.compare(second.last_opened_at, first.last_opened_at) == :gt
    end

    test "three pushes of the same path produce open_count = 3" do
      {:ok, _} = Library.push_recent("/tmp/three.md")
      {:ok, _} = Library.push_recent("/tmp/three.md")
      {:ok, third} = Library.push_recent("/tmp/three.md")
      assert third.open_count == 3
    end
  end

  describe "reset_recents/0" do
    test "deletes all recent files" do
      {:ok, _} = Library.push_recent("/tmp/x.md")
      {:ok, _} = Library.push_recent("/tmp/y.md")
      assert length(Library.list_recent!()) == 2

      :ok = Library.reset_recents()
      assert Library.list_recent!() == []
    end

    test "is idempotent when already empty" do
      assert :ok = Library.reset_recents()
      assert :ok = Library.reset_recents()
    end
  end
end
