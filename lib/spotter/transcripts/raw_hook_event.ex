defmodule Spotter.Transcripts.RawHookEvent do
  @moduledoc false

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "raw_hook_events"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :session_id,
        :hook_event_name,
        :tool_name,
        :tool_use_id,
        :hook_payload,
        :env,
        :captured_at
      ]
    end

    create :upsert do
      accept [
        :session_id,
        :hook_event_name,
        :tool_name,
        :tool_use_id,
        :hook_payload,
        :env,
        :captured_at
      ]

      upsert? true
      upsert_identity :unique_event
      upsert_fields [:hook_payload, :env, :captured_at]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :session_id, :string, allow_nil?: false
    attribute :hook_event_name, :string, allow_nil?: false
    attribute :tool_name, :string
    attribute :tool_use_id, :string
    attribute :hook_payload, :map, allow_nil?: false
    attribute :env, :map, allow_nil?: false, default: %{}
    attribute :captured_at, :utc_datetime_usec, allow_nil?: false

    create_timestamp :inserted_at
  end

  identities do
    identity :unique_event, [:session_id, :tool_use_id, :hook_event_name], nils_distinct?: false
  end
end
