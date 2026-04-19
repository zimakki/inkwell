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

  actions do
    defaults [:read]

    create :seed do
      accept [:path, :last_opened_at, :open_count]
    end

    read :list_recent do
      prepare build(sort: [last_opened_at: :desc], limit: 20)
    end

    create :push_recent do
      accept [:path]
      upsert? true
      upsert_identity :unique_path
      upsert_fields [:last_opened_at, :open_count]

      change set_attribute(:last_opened_at, &DateTime.utc_now/0)
      change set_attribute(:open_count, 1)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :path, :string, allow_nil?: false
    attribute :last_opened_at, :utc_datetime_usec, allow_nil?: false
    attribute :open_count, :integer, allow_nil?: false, default: 0
  end

  identities do
    identity :unique_path, [:path]
  end
end
