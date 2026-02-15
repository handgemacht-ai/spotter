defmodule Spotter.Transcripts.ProjectIngestState do
  @moduledoc "Rate-limiting state for commit ingestion per project."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "project_ingest_states"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :project_id,
        :last_commit_ingest_at,
        :heatmap_last_run_at,
        :heatmap_window_days,
        :co_change_last_run_at,
        :co_change_window_days
      ]

      upsert? true
      upsert_identity :unique_project

      upsert_fields [
        :last_commit_ingest_at,
        :heatmap_last_run_at,
        :heatmap_window_days,
        :co_change_last_run_at,
        :co_change_window_days
      ]
    end

    update :update do
      primary? true

      accept [
        :last_commit_ingest_at,
        :heatmap_last_run_at,
        :heatmap_window_days,
        :co_change_last_run_at,
        :co_change_window_days
      ]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :last_commit_ingest_at, :utc_datetime_usec

    attribute :heatmap_last_run_at, :utc_datetime_usec, allow_nil?: true
    attribute :heatmap_window_days, :integer, allow_nil?: false, default: 30
    attribute :co_change_last_run_at, :utc_datetime_usec, allow_nil?: true
    attribute :co_change_window_days, :integer, allow_nil?: false, default: 30

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end
  end

  identities do
    identity :unique_project, [:project_id]
  end
end
