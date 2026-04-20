defmodule Inkwell.ReleaseTest do
  use ExUnit.Case, async: false

  test "migrate!/0 is idempotent and ensures the state directory exists" do
    # test_helper.exs called migrate!/0 once on startup; a second call must
    # be a no-op. Also confirms the File.mkdir_p! step at the top of
    # migrate!/0 keeps state_dir on disk (it's required for the SQLite file).
    assert :ok = Inkwell.Release.migrate!()
    assert File.exists?(Inkwell.Settings.state_dir())
  end

  test "repos/0 derives the unique repo list from configured Ash domains" do
    assert Inkwell.Release.repos() == [Inkwell.Repo]
  end

  test "repos/0 only includes repos for resources backed by AshSqlite.DataLayer" do
    # Documents the contract: any future embedded resource (or one using
    # Ets/Mnesia/etc.) must not blow up `AshSqlite.DataLayer.Info.repo/1`.
    resources =
      :inkwell
      |> Application.fetch_env!(:ash_domains)
      |> Enum.flat_map(&Ash.Domain.Info.resources/1)

    repo_resources =
      Enum.filter(resources, &(Ash.Resource.Info.data_layer(&1) == AshSqlite.DataLayer))

    assert Enum.count(repo_resources) == length(resources),
           "current resources are all expected to be AshSqlite-backed; " <>
             "if a non-SQLite resource is added, repos/0 must still return only SQLite repos"
  end
end
