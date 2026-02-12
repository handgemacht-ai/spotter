defmodule Spotter.Transcripts.CodeHotspot do
  @moduledoc "AI-scored code snippet with rubric factors for review prioritization."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "code_hotspots"
    repo Spotter.Repo
  end

  json_api do
    type "code_hotspot"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :relative_path,
        :snippet,
        :line_start,
        :line_end,
        :overall_score,
        :rubric,
        :model_used,
        :scored_at,
        :project_id,
        :file_heatmap_id
      ]

      upsert? true
      upsert_identity :unique_project_snippet
    end

    update :update do
      primary? true

      accept [
        :snippet,
        :overall_score,
        :rubric,
        :model_used,
        :scored_at
      ]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :relative_path, :string, allow_nil?: false
    attribute :snippet, :string, allow_nil?: false
    attribute :line_start, :integer, allow_nil?: false
    attribute :line_end, :integer, allow_nil?: false

    attribute :overall_score, :float do
      allow_nil? false
      default 0.0
      constraints min: 0.0, max: 100.0
    end

    attribute :rubric, :map do
      allow_nil? false
      default %{}

      description "Rubric factor scores: complexity, duplication, error_handling, test_coverage, change_risk (each 0-100)"
    end

    attribute :model_used, :string, allow_nil?: false
    attribute :scored_at, :utc_datetime_usec, allow_nil?: false

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end

    belongs_to :file_heatmap, Spotter.Transcripts.FileHeatmap do
      allow_nil? true
    end
  end

  identities do
    identity :unique_project_snippet, [:project_id, :relative_path, :line_start]
  end
end
