defmodule Spotter.Transcripts.SessionRework do
  @moduledoc false

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "session_reworks"
    repo Spotter.Repo
  end

  json_api do
    type "session_rework"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :tool_use_id,
        :file_path,
        :relative_path,
        :occurrence_index,
        :first_tool_use_id,
        :event_timestamp,
        :detection_source,
        :session_id
      ]
    end

    create :upsert do
      accept [
        :tool_use_id,
        :file_path,
        :relative_path,
        :occurrence_index,
        :first_tool_use_id,
        :event_timestamp,
        :detection_source,
        :session_id
      ]

      upsert? true
      upsert_identity :unique_session_tool_use

      upsert_fields [
        :file_path,
        :relative_path,
        :occurrence_index,
        :first_tool_use_id,
        :event_timestamp,
        :detection_source
      ]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :tool_use_id, :string, allow_nil?: false
    attribute :file_path, :string, allow_nil?: false
    attribute :relative_path, :string
    attribute :occurrence_index, :integer, allow_nil?: false
    attribute :first_tool_use_id, :string, allow_nil?: false
    attribute :event_timestamp, :utc_datetime_usec

    attribute :detection_source, :atom do
      allow_nil? false
      default :transcript_sync
      constraints one_of: [:transcript_sync]
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end
  end

  identities do
    identity :unique_session_tool_use, [:session_id, :tool_use_id]
  end
end
