defmodule Inkwell.ReleaseTest do
  use ExUnit.Case, async: false

  test "migrate!/0 is idempotent and ensures the state directory exists" do
    # test_helper.exs called migrate!/0 once on startup; a second call must
    # be a no-op. Also confirms the File.mkdir_p! step at the top of
    # migrate!/0 keeps state_dir on disk (it's required for the SQLite file).
    assert :ok = Inkwell.Release.migrate!()
    assert File.exists?(Inkwell.Settings.state_dir())
  end
end
