defmodule Inkwell.Library do
  @moduledoc """
  Ash domain owning persistent reader-history primitives.

  For now: `Inkwell.Library.RecentFile` — recently opened markdown files.
  Future PRs will add favorites and tags to this domain.
  """

  use Ash.Domain

  resources do
    resource Inkwell.Library.RecentFile do
      define :list_recent, action: :list_recent
      define :push_recent, action: :push_recent, args: [:path]
    end
  end

  def reset_recents do
    Ash.bulk_destroy!(Inkwell.Library.RecentFile, :destroy, %{}, return_errors?: true)
    :ok
  end

  @doc """
  Convenience: returns just the paths of recent files, in the same
  order as `list_recent/0`. Used by the picker where only the path
  string is needed.
  """
  def list_recent_paths do
    list_recent!() |> Enum.map(& &1.path)
  end
end
