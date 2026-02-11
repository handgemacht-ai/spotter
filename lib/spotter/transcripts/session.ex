defmodule Spotter.Transcripts.Session do
  @moduledoc "A Claude Code session within a project."
  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "sessions"
    repo Spotter.Repo
  end

  json_api do
    type "session"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :session_id,
        :slug,
        :transcript_dir,
        :cwd,
        :git_branch,
        :version,
        :started_at,
        :ended_at,
        :schema_version,
        :message_count,
        :project_id
      ]
    end

    update :update do
      primary? true

      accept [
        :slug,
        :cwd,
        :git_branch,
        :version,
        :started_at,
        :ended_at,
        :schema_version,
        :message_count
      ]
    end

    update :hide do
      accept []
      change set_attribute(:hidden_at, &DateTime.utc_now/0)
    end

    update :unhide do
      accept []
      change set_attribute(:hidden_at, nil)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :session_id, :uuid do
      allow_nil? false
    end

    attribute :slug, :string
    attribute :transcript_dir, :string, allow_nil?: false
    attribute :cwd, :string
    attribute :git_branch, :string
    attribute :version, :string

    attribute :started_at, :utc_datetime_usec
    attribute :ended_at, :utc_datetime_usec

    attribute :schema_version, :integer do
      allow_nil? false
      default 1
    end

    attribute :message_count, :integer
    attribute :hidden_at, :utc_datetime_usec, allow_nil?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end

    has_many :messages, Spotter.Transcripts.Message
    has_many :subagents, Spotter.Transcripts.Subagent
    has_many :annotations, Spotter.Transcripts.Annotation
    has_many :tool_calls, Spotter.Transcripts.ToolCall
  end

  identities do
    identity :unique_session_id, [:session_id]
  end
end
