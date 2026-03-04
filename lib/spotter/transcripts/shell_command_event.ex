defmodule Spotter.Transcripts.ShellCommandEvent do
  @moduledoc false

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "shell_command_events"
    repo Spotter.Repo
  end

  @accepted_fields [
    :session_id,
    :external_session_id,
    :project_id,
    :tool_use_id,
    :tool_name,
    :command,
    :command_path,
    :hook_event_name,
    :phase,
    :finish_status,
    :captured_at,
    :raw_hook_event_id
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
      upsert_identity :unique_event_command
      upsert_fields [:finish_status, :captured_at]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :session_id, :uuid, allow_nil?: false
    attribute :external_session_id, :string, allow_nil?: false
    attribute :project_id, :uuid, allow_nil?: false
    attribute :tool_use_id, :string, allow_nil?: false
    attribute :tool_name, :string
    attribute :command, :string, allow_nil?: false
    attribute :command_path, :string, allow_nil?: false
    attribute :hook_event_name, :string, allow_nil?: false

    attribute :phase, :atom do
      allow_nil? false
      constraints one_of: [:start, :finish]
    end

    attribute :finish_status, :atom do
      constraints one_of: [:ok, :error, :unknown]
    end

    attribute :captured_at, :utc_datetime_usec, allow_nil?: false
    attribute :raw_hook_event_id, :string, allow_nil?: false

    create_timestamp :inserted_at
  end

  identities do
    identity :unique_event_command, [:raw_hook_event_id, :command_path, :phase]
  end
end
