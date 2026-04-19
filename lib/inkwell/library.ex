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
    Inkwell.Library.RecentFile
    |> Ash.read!()
    |> Ash.bulk_destroy!(:destroy, %{}, return_errors?: true)

    :ok
  end
end
