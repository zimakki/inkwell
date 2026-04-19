defmodule Inkwell.Library do
  @moduledoc """
  Ash domain owning persistent reader-history primitives.

  For now: `Inkwell.Library.RecentFile` — recently opened markdown files.
  Future PRs will add favorites and tags to this domain.
  """

  use Ash.Domain

  resources do
    resource Inkwell.Library.RecentFile
  end
end
