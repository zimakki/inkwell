defmodule Inkwell.WatcherTest do
  use ExUnit.Case, async: false

  setup do
    base = Path.join(System.tmp_dir!(), "inkwell-watcher-#{System.unique_integer([:positive])}")
    File.mkdir_p!(base)
    test_file = Path.join(base, "watched.md")
    File.write!(test_file, "# Original")

    on_exit(fn -> File.rm_rf!(base) end)

    {:ok, %{test_file: test_file, base: base}}
  end

  test "ensure_file registers a file for watching", %{test_file: test_file} do
    :ok = Inkwell.Watcher.ensure_file(test_file)
    resolved = Inkwell.Watcher.resolve_path(test_file)
    assert resolved in Inkwell.Watcher.watched_files()
  end

  test "watched_files returns all registered files", %{base: base} do
    file1 = Path.join(base, "one.md")
    file2 = Path.join(base, "two.md")
    File.write!(file1, "# One")
    File.write!(file2, "# Two")

    Inkwell.Watcher.ensure_file(file1)
    Inkwell.Watcher.ensure_file(file2)

    watched = Inkwell.Watcher.watched_files()
    assert Inkwell.Watcher.resolve_path(file1) in watched
    assert Inkwell.Watcher.resolve_path(file2) in watched
  end

  test "broadcast_nav dispatches payload via PubSub to subscribers", %{test_file: test_file} do
    Inkwell.Watcher.ensure_file(test_file)
    expanded = Inkwell.Watcher.resolve_path(test_file)
    :ok = Phoenix.PubSub.subscribe(Inkwell.PubSub, "file:" <> expanded)

    Inkwell.Watcher.broadcast_nav("<p>Hi</p>", [%{level: 2, text: "Hi", id: "hi"}], [], expanded)

    assert_receive {:reload, %{html: "<p>Hi</p>", headings: [_]}}, 1000
  end

  test "rebroadcast_all handles deleted files gracefully", %{base: base} do
    deleted_file = Path.join(base, "deleted.md")
    File.write!(deleted_file, "# Will be deleted")
    Inkwell.Watcher.ensure_file(deleted_file)
    File.rm!(deleted_file)

    # Should not crash
    Inkwell.Watcher.rebroadcast_all()
  end

  test "handle_info with :renamed event triggers broadcast", %{test_file: test_file} do
    :ok = Inkwell.Watcher.ensure_file(test_file)
    expanded = Inkwell.Watcher.resolve_path(test_file)
    :ok = Phoenix.PubSub.subscribe(Inkwell.PubSub, "file:" <> expanded)

    watcher_pid = lookup_watcher!(Path.dirname(expanded))
    send(watcher_pid, {:file_event, self(), {expanded, [:renamed]}})

    assert_receive {:reload, %{html: _}}, 1000
  end

  test "handle_info with :created event triggers broadcast", %{test_file: test_file} do
    :ok = Inkwell.Watcher.ensure_file(test_file)
    expanded = Inkwell.Watcher.resolve_path(test_file)
    :ok = Phoenix.PubSub.subscribe(Inkwell.PubSub, "file:" <> expanded)

    watcher_pid = lookup_watcher!(Path.dirname(expanded))
    send(watcher_pid, {:file_event, self(), {expanded, [:created, :modified]}})

    assert_receive {:reload, %{html: _}}, 1000
  end

  test "resolve_path follows symlinks" do
    base = Path.join(System.tmp_dir!(), "inkwell-symlink-#{System.unique_integer([:positive])}")
    target = Path.join(base, "target")
    link = Path.join(base, "link")
    File.mkdir_p!(target)
    File.ln_s!(target, link)

    on_exit(fn -> File.rm_rf!(base) end)

    resolved = Inkwell.Watcher.resolve_path(link)
    assert resolved == Inkwell.Watcher.resolve_path(target)
    refute resolved == link
  end

  test "handle_info ignores events for untracked files", %{base: base} do
    tracked = Path.join(base, "tracked.md")
    untracked = Path.join(base, "untracked.md")
    File.write!(tracked, "# Tracked")
    File.write!(untracked, "# Untracked")

    :ok = Inkwell.Watcher.ensure_file(tracked)
    expanded_tracked = Inkwell.Watcher.resolve_path(tracked)
    expanded_untracked = Inkwell.Watcher.resolve_path(untracked)

    :ok = Phoenix.PubSub.subscribe(Inkwell.PubSub, "file:" <> expanded_tracked)

    watcher_pid = lookup_watcher!(Path.dirname(expanded_tracked))
    send(watcher_pid, {:file_event, self(), {expanded_untracked, [:modified]}})

    refute_receive {:reload, _}, 200
  end

  defp lookup_watcher!(dir) do
    case Registry.lookup(Inkwell.WatcherRegistry, dir) do
      [{pid, _}] -> pid
      [] -> raise "no watcher for dir #{dir}"
    end
  end

  describe "lifecycle" do
    test "watcher terminates when its last subscriber pid dies", %{base: base} do
      file = Path.join(base, "ephemeral.md")
      File.write!(file, "# E")

      parent = self()

      {:ok, subscriber} =
        Task.start(fn ->
          Inkwell.Watcher.ensure_file(file)
          send(parent, :registered)

          receive do
            :exit -> :ok
          end
        end)

      assert_receive :registered, 1000

      dir = Path.dirname(Inkwell.Watcher.resolve_path(file))
      watcher_pid = lookup_watcher!(dir)
      ref = Process.monitor(watcher_pid)

      send(subscriber, :exit)

      assert_receive {:DOWN, ^ref, :process, ^watcher_pid, _reason}, 2000
    end
  end
end
