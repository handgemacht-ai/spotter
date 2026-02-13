defmodule Spotter.Transcripts.PromptPattern do
  @moduledoc "A repeated prompt pattern discovered by an analysis run."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "prompt_patterns"
    repo Spotter.Repo
  end

  json_api do
    type "prompt_pattern"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :run_id,
        :needle,
        :label,
        :count_total,
        :project_counts,
        :examples,
        :confidence
      ]

      upsert? true
      upsert_identity :unique_run_needle
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :needle, :string, allow_nil?: false
    attribute :label, :string, allow_nil?: false
    attribute :count_total, :integer, allow_nil?: false, default: 0

    attribute :project_counts, :map do
      allow_nil? false
      default %{}
    end

    attribute :examples, :map do
      allow_nil? false
      default %{"items" => []}
    end

    attribute :confidence, :float, allow_nil?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :run, Spotter.Transcripts.PromptPatternRun, allow_nil?: false
  end

  identities do
    identity :unique_run_needle, [:run_id, :needle]
  end
end
