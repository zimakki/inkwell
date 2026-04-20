defmodule Inkwell.Library.Changes.BumpOrSetOpenCount do
  @moduledoc """
  Upsert change for `push_recent`:

  * On INSERT (new path) sets `open_count` to 1.
  * On UPDATE (ON CONFLICT path match) atomically increments
    `open_count` by 1.

  Uses `Ash.Changeset.atomic_set/3` for the INSERT value and
  `Ash.Changeset.atomic_update/3` for the ON CONFLICT value.
  The data layer applies both together during an upsert, so the
  count stays correct under concurrent pushes.
  """

  use Ash.Resource.Change
  require Ash.Expr

  @impl true
  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.atomic_set(:open_count, Ash.Expr.expr(1))
    |> Ash.Changeset.atomic_update(:open_count, Ash.Expr.expr(open_count + 1))
  end
end
