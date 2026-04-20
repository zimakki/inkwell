defmodule Inkwell.DaemonTest do
  use ExUnit.Case, async: false

  test "ensure_started creates the state directory when missing" do
    tmp_dir = Path.join(System.tmp_dir!(), "inkwell-daemon-#{System.unique_integer([:positive])}")
    state_dir = Path.join(System.user_home!(), ".inkwell")
    backup_dir = state_dir <> ".bak-#{System.unique_integer([:positive])}"
    fake_exec = Path.join(tmp_dir, "inkwell")
    old_burrito_bin = System.get_env("__BURRITO_BIN_PATH")

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    File.write!(fake_exec, "#!/bin/sh\nsleep 5\n")
    File.chmod!(fake_exec, 0o755)

    if File.exists?(state_dir) do
      File.rename!(state_dir, backup_dir)
    end

    on_exit(fn ->
      restore_env("__BURRITO_BIN_PATH", old_burrito_bin)
      File.rm_rf!(state_dir)

      if File.exists?(backup_dir) do
        File.rename!(backup_dir, state_dir)
      end

      File.rm_rf!(tmp_dir)
    end)

    System.put_env("__BURRITO_BIN_PATH", fake_exec)

    refute File.exists?(state_dir)

    task = Task.async(fn -> Inkwell.Daemon.ensure_started(theme: "dark") end)

    assert_dir_exists(state_dir)

    Task.shutdown(task, :brutal_kill)
  end

  defp assert_dir_exists(path, attempts_left \\ 20)

  defp assert_dir_exists(path, attempts_left) when attempts_left > 0 do
    if File.dir?(path) do
      assert true
    else
      Process.sleep(50)
      assert_dir_exists(path, attempts_left - 1)
    end
  end

  defp assert_dir_exists(path, 0) do
    flunk("expected #{path} to exist")
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  describe "pid_alive?/1" do
    test "returns true for the current OS process" do
      assert Inkwell.Daemon.pid_alive?(System.pid()) == true
    end

    test "returns false for a clearly-nonexistent PID" do
      # 7-digit PIDs aren't impossible but the odds of clash with a live
      # process during a test are vanishingly small; a rerun would surface it.
      assert Inkwell.Daemon.pid_alive?("9999999") == false
    end

    test "returns false for malformed input" do
      assert Inkwell.Daemon.pid_alive?("not a pid") == false
      assert Inkwell.Daemon.pid_alive?("") == false
    end
  end
end
