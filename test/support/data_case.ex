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
      alias Inkwell.Repo
    end
  end

  setup do
    # Future resources (favorites, tags) get added here.
    for schema <- [Inkwell.Library.RecentFile] do
      Inkwell.Repo.delete_all(schema)
    end

    :ok
  end
end
