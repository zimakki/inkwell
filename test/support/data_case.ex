defmodule Inkwell.DataCase do
  @moduledoc """
  ExUnit case template for tests that hit the Repo.

  SQLite doesn't support the Ecto sandbox the way Postgres does, so we
  use a shared file-backed test DB and delete all RecentFile rows in
  `setup`. Tests that `use Inkwell.DataCase` must run with `async: false`.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Inkwell.DataCase
    end
  end

  setup do
    Inkwell.Library.reset_recents()
  end

  @doc """
  Inserts a `RecentFile` row with explicit `last_opened_at` / `open_count`.
  Wraps the `:seed` action so tests don't call it directly from outside
  `test/support/`.
  """
  def seed_recent(path, last_opened_at, open_count \\ 1) do
    Inkwell.Library.RecentFile
    |> Ash.Changeset.for_create(:seed, %{
      path: path,
      last_opened_at: last_opened_at,
      open_count: open_count
    })
    |> Ash.create!()
  end
end
