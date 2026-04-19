defmodule Inkwell.Library.RecentFile do
  @moduledoc """
  Ash resource tracking recently opened markdown files.

  Replaces `Inkwell.History` (ephemeral Agent). Recents persist across
  daemon restarts. Schema owns `path` (unique), `last_opened_at`, and
  `open_count`. Actions are defined in sibling tasks.
  """

  use Ash.Resource,
    domain: Inkwell.Library,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "recent_files"
    repo Inkwell.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :path, :string, allow_nil?: false, public?: true
    attribute :last_opened_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :open_count, :integer, allow_nil?: false, default: 0, public?: true
  end

  identities do
    identity :unique_path, [:path]
  end

  actions do
    defaults [:read]
  end
end
