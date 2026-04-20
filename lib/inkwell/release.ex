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

    Enum.each(repos(), &migrate_repo!/1)
  end

  @doc """
  Returns the unique list of repos owned by configured Ash domains.

  Used by `migrate!/0` and exposed publicly so release tasks can iterate
  the same set of repos for rollback or other ops.
  """
  def repos do
    :inkwell
    |> Application.fetch_env!(:ash_domains)
    |> Enum.flat_map(&Ash.Domain.Info.resources/1)
    |> Enum.filter(&ash_sqlite?/1)
    |> Enum.map(&AshSqlite.DataLayer.Info.repo/1)
    |> Enum.uniq()
  end

  defp ash_sqlite?(resource) do
    Ash.Resource.Info.data_layer(resource) == AshSqlite.DataLayer
  end

  defp migrate_repo!(repo) do
    case Ecto.Migrator.with_repo(repo, fn repo ->
           Ecto.Migrator.run(repo, :up, all: true)
         end) do
      {:ok, _, _} ->
        :ok

      {:error, reason} ->
        raise "Inkwell.Release.migrate! failed for #{inspect(repo)}: #{inspect(reason)}"
    end
  end
end
