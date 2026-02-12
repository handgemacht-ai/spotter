defmodule Spotter.Transcripts.CoChangeGroup do
  @moduledoc "A group of files or directories that frequently change together."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "co_change_groups"
    repo Spotter.Repo
  end

  json_api do
    type "co_change_group"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :scope,
        :group_key,
        :members,
        :frequency_30d,
        :last_seen_at,
        :project_id
      ]

      upsert? true
      upsert_identity :unique_project_scope_group
      upsert_fields [:members, :frequency_30d, :last_seen_at]
    end

    update :update do
      primary? true

      accept [
        :members,
        :frequency_30d,
        :last_seen_at
      ]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :scope, :atom do
      allow_nil? false
      constraints one_of: [:file, :directory]
    end

    attribute :group_key, :string, allow_nil?: false
    attribute :members, {:array, :string}, allow_nil?: false, default: []
    attribute :frequency_30d, :integer, allow_nil?: false, default: 0
    attribute :last_seen_at, :utc_datetime_usec

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end
  end

  identities do
    identity :unique_project_scope_group, [:project_id, :scope, :group_key]
  end
end
