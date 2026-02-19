defmodule Spotter.Transcripts.SessionCommitLink do
  @moduledoc "Links a session to a commit with type and confidence."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  require OpenTelemetry.Tracer, as: Tracer

  sqlite do
    table "session_commit_links"
    repo Spotter.Repo
  end

  json_api do
    type "session_commit_link"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :link_type,
        :confidence,
        :evidence,
        :session_id,
        :commit_id
      ]

      upsert? true
      upsert_identity :unique_session_commit_link_type
      upsert_fields [:confidence, :evidence]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :link_type, :atom do
      allow_nil? false

      constraints one_of: [
                    :observed_in_session,
                    :descendant_of_observed,
                    :patch_match,
                    :file_overlap
                  ]
    end

    attribute :confidence, :float do
      allow_nil? false
      constraints min: 0.0, max: 1.0
    end

    attribute :evidence, :map

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end

    belongs_to :commit, Spotter.Transcripts.Commit do
      allow_nil? false
    end
  end

  identities do
    identity :unique_session_commit_link_type, [:session_id, :commit_id, :link_type]
  end

end
