defmodule Spotter.Transcripts.InstructionsLoadedEvent do
  @moduledoc false

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "instructions_loaded_events"
    repo Spotter.Repo
  end

  @accepted_fields [
    :raw_hook_event_id,
    :external_session_id,
    :session_id,
    :project_id,
    :file_path,
    :memory_type,
    :load_reason,
    :bytes_loaded,
    :lines_loaded,
    :size_status,
    :captured_at
  ]

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept @accepted_fields
    end

    create :upsert do
      accept @accepted_fields

      upsert? true
      upsert_identity :unique_raw_event
      upsert_fields [:bytes_loaded, :lines_loaded, :size_status, :captured_at]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :raw_hook_event_id, :string, allow_nil?: false
    attribute :external_session_id, :string
    attribute :session_id, :uuid
    attribute :project_id, :uuid
    attribute :file_path, :string, allow_nil?: false
    attribute :memory_type, :string
    attribute :load_reason, :string
    attribute :bytes_loaded, :integer, default: 0
    attribute :lines_loaded, :integer, default: 0
    attribute :size_status, :string, default: "unknown"
    attribute :captured_at, :utc_datetime_usec, allow_nil?: false

    create_timestamp :inserted_at
  end

  identities do
    identity :unique_raw_event, [:raw_hook_event_id]
  end
end
