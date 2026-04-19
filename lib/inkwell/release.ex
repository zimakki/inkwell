defmodule Inkwell.Release do
  @moduledoc """
  Runtime hooks for the release. Owns boot-time database migration.

  Called from `Inkwell.Application.start/2` in daemon mode before the
  supervision tree is built. Any failure raises and kills the OTP
  application start — this is the hard-fail policy (see spec).
  """

  @doc """
  Ensure the state directory exists, then run all pending migrations.

  Raises on any failure: missing directory perms, unable to open DB,
  migration SQL errors, corruption.
  """
  def migrate! do
    File.mkdir_p!(Inkwell.Settings.state_dir())

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Inkwell.Repo, fn repo ->
        Ecto.Migrator.run(repo, :up, all: true)
      end)

    :ok
  end
end
