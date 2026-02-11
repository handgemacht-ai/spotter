defmodule Spotter.Transcripts.Subagent do
  @moduledoc "A subagent spawned within a Claude Code session."
  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "subagents"
    repo Spotter.Repo
  end

  json_api do
    type "subagent"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :agent_id,
        :slug,
        :started_at,
        :ended_at,
        :message_count,
        :session_id
      ]
    end

    update :update do
      primary? true

      accept [
        :slug,
        :started_at,
        :ended_at,
        :message_count
      ]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :agent_id, :string do
      allow_nil? false
    end

    attribute :slug, :string
    attribute :started_at, :utc_datetime_usec
    attribute :ended_at, :utc_datetime_usec
    attribute :message_count, :integer

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end

    has_many :messages, Spotter.Transcripts.Message
    has_many :annotations, Spotter.Transcripts.Annotation
  end

  identities do
    identity :unique_agent_per_session, [:session_id, :agent_id]
  end
end
