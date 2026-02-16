defmodule Spotter.Transcripts.SessionDistillation do
  @moduledoc "Stores the distilled summary artifact for a completed session."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "session_distillations"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      primary? true

      accept [
        :status,
        :model_used,
        :summary_json,
        :summary_text,
        :raw_response_text,
        :error_reason,
        :input_stats,
        :session_id
      ]

      upsert? true
      upsert_identity :unique_session_distillation

      upsert_fields [
        :status,
        :model_used,
        :summary_json,
        :summary_text,
        :raw_response_text,
        :error_reason,
        :input_stats
      ]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:completed, :skipped, :error]
    end

    attribute :model_used, :string
    attribute :summary_json, :map
    attribute :summary_text, :string
    attribute :raw_response_text, :string
    attribute :error_reason, :string

    attribute :input_stats, :map

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end
  end

  identities do
    identity :unique_session_distillation, [:session_id]
  end
end
