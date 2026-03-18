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
    assert test_file in Inkwell.Watcher.watched_files()
  end

  test "watched_files returns all registered files", %{base: base} do
    file1 = Path.join(base, "one.md")
    file2 = Path.join(base, "two.md")
    File.write!(file1, "# One")
    File.write!(file2, "# Two")

    Inkwell.Watcher.ensure_file(file1)
    Inkwell.Watcher.ensure_file(file2)

    watched = Inkwell.Watcher.watched_files()
    assert file1 in watched
    assert file2 in watched
  end

  test "broadcast_nav dispatches JSON to registered clients", %{test_file: test_file} do
    Inkwell.Watcher.ensure_file(test_file)
    expanded = Path.expand(test_file)
    Registry.register(Inkwell.Registry, {:ws_clients, expanded}, [])

    Inkwell.Watcher.broadcast_nav("<p>Hi</p>", [%{level: 2, text: "Hi", id: "hi"}], [], expanded)

    assert_receive {:reload, payload}, 1000
    assert %{"html" => "<p>Hi</p>", "headings" => [_]} = Jason.decode!(payload)
  end

  test "rebroadcast_all handles deleted files gracefully", %{base: base} do
    deleted_file = Path.join(base, "deleted.md")
    File.write!(deleted_file, "# Will be deleted")
    Inkwell.Watcher.ensure_file(deleted_file)
    File.rm!(deleted_file)

    # Should not crash
    Inkwell.Watcher.rebroadcast_all()
  end
end
