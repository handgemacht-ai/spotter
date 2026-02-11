defmodule Spotter.Transcripts.ToolCall do
  @moduledoc false

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "tool_calls"
    repo Spotter.Repo
  end

  json_api do
    type "tool_call"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :tool_use_id,
        :tool_name,
        :is_error,
        :error_content,
        :session_id
      ]
    end

    create :upsert do
      accept [
        :tool_use_id,
        :tool_name,
        :is_error,
        :error_content,
        :session_id
      ]

      upsert? true
      upsert_identity :unique_tool_use_id
      upsert_fields [:tool_name, :is_error, :error_content]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :tool_use_id, :string, allow_nil?: false
    attribute :tool_name, :string, allow_nil?: false

    attribute :is_error, :boolean do
      allow_nil? false
      default false
    end

    attribute :error_content, :string

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end
  end

  identities do
    identity :unique_tool_use_id, [:tool_use_id]
  end
end
