defmodule Spotter.Transcripts.FileHeatmap do
  @moduledoc "Per-file change frequency and recency data for heatmap visualization."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "file_heatmaps"
    repo Spotter.Repo
  end

  json_api do
    type "file_heatmap"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :relative_path,
        :change_count_30d,
        :heat_score,
        :last_changed_at,
        :size_bytes,
        :loc,
        :project_id
      ]

      upsert? true
      upsert_identity :unique_project_path
    end

    update :update do
      primary? true

      accept [
        :change_count_30d,
        :heat_score,
        :last_changed_at,
        :size_bytes,
        :loc
      ]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :relative_path, :string, allow_nil?: false
    attribute :change_count_30d, :integer, allow_nil?: false, default: 0
    attribute :last_changed_at, :utc_datetime_usec

    attribute :heat_score, :float do
      allow_nil? false
      default 0.0
      constraints min: 0.0, max: 100.0
    end

    attribute :size_bytes, :integer
    attribute :loc, :integer

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end
  end

  identities do
    identity :unique_project_path, [:project_id, :relative_path]
  end
end
