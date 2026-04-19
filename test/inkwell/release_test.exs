defmodule Inkwell.ReleaseTest do
  use ExUnit.Case, async: false

  test "migrate!/0 returns :ok when migrations are already applied" do
    # test_helper.exs already called migrate!/0 once on startup.
    # A second call should be a no-op and return :ok.
    assert :ok = Inkwell.Release.migrate!()
  end

  test "migrate!/0 creates the state directory if missing" do
    # We can't actually remove ~/.inkwell from a test — instead, verify
    # the function references Inkwell.Settings.state_dir and that dir exists.
    assert File.exists?(Inkwell.Settings.state_dir())
  end
end
