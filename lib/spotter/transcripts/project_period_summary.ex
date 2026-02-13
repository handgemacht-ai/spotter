defmodule Spotter.Transcripts.ProjectPeriodSummary do
  @moduledoc "Stores a distilled summary for a project within a date bucket."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "project_period_summaries"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      primary? true

      accept [
        :bucket_kind,
        :bucket_start_date,
        :timezone,
        :default_branch,
        :included_session_ids,
        :included_commit_hashes,
        :summary_json,
        :summary_text,
        :model_used,
        :computed_at,
        :project_id
      ]

      upsert? true
      upsert_identity :unique_period

      upsert_fields [
        :included_session_ids,
        :included_commit_hashes,
        :summary_json,
        :summary_text,
        :model_used,
        :computed_at
      ]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :bucket_kind, :atom do
      allow_nil? false
      constraints one_of: [:day, :week, :month]
    end

    attribute :bucket_start_date, :date do
      allow_nil? false
    end

    attribute :timezone, :string do
      allow_nil? false
    end

    attribute :default_branch, :string do
      allow_nil? false
    end

    attribute :included_session_ids, {:array, :string} do
      allow_nil? false
      default []
    end

    attribute :included_commit_hashes, {:array, :string} do
      allow_nil? false
      default []
    end

    attribute :summary_json, :map
    attribute :summary_text, :string
    attribute :model_used, :string
    attribute :computed_at, :utc_datetime_usec

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end
  end

  identities do
    identity :unique_period, [
      :project_id,
      :bucket_kind,
      :bucket_start_date,
      :timezone,
      :default_branch
    ]
  end
end
