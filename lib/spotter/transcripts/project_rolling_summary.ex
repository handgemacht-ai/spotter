defmodule Spotter.Transcripts.ProjectRollingSummary do
  @moduledoc "Stores a rolling summary across recent date buckets for a project."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "project_rolling_summaries"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      primary? true

      accept [
        :bucket_kind,
        :timezone,
        :default_branch,
        :lookback_days,
        :included_bucket_start_dates,
        :summary_json,
        :summary_text,
        :model_used,
        :computed_at,
        :project_id
      ]

      upsert? true
      upsert_identity :unique_rolling

      upsert_fields [
        :included_bucket_start_dates,
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

    attribute :timezone, :string do
      allow_nil? false
    end

    attribute :default_branch, :string do
      allow_nil? false
    end

    attribute :lookback_days, :integer do
      allow_nil? false
    end

    attribute :included_bucket_start_dates, {:array, :string} do
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
    identity :unique_rolling, [
      :project_id,
      :bucket_kind,
      :timezone,
      :default_branch,
      :lookback_days
    ]
  end
end
