defmodule Spotter.Transcripts.Message do
  @moduledoc "A message within a Claude Code session transcript."
  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "messages"
    repo Spotter.Repo
  end

  json_api do
    type "message"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :uuid,
        :parent_uuid,
        :message_id,
        :type,
        :role,
        :content,
        :raw_payload,
        :timestamp,
        :is_sidechain,
        :agent_id,
        :tool_use_id,
        :session_id,
        :subagent_id
      ]
    end

    create :upsert do
      accept [
        :uuid,
        :parent_uuid,
        :message_id,
        :type,
        :role,
        :content,
        :raw_payload,
        :timestamp,
        :is_sidechain,
        :agent_id,
        :tool_use_id,
        :session_id,
        :subagent_id
      ]

      upsert? true
      upsert_identity :unique_session_uuid
      upsert_fields [:content, :raw_payload, :type, :role]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :uuid, :string do
      allow_nil? false
      public? true
    end

    attribute :parent_uuid, :string
    attribute :message_id, :string

    attribute :type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :user,
                    :assistant,
                    :tool_use,
                    :tool_result,
                    :progress,
                    :thinking,
                    :system,
                    :file_history_snapshot
                  ]
    end

    attribute :role, :atom do
      public? true
      constraints one_of: [:user, :assistant, :system]
    end

    attribute :content, :map, public?: true
    attribute :raw_payload, :map

    attribute :timestamp, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :is_sidechain, :boolean do
      default false
    end

    attribute :agent_id, :string
    attribute :tool_use_id, :string

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end

    belongs_to :subagent, Spotter.Transcripts.Subagent do
      allow_nil? true
    end

    has_many :annotation_refs, Spotter.Transcripts.AnnotationMessageRef
  end

  identities do
    identity :unique_session_uuid, [:session_id, :uuid]
  end
end
