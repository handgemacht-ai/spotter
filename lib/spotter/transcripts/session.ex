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
    defaults [:destroy]

    read :read do
      primary? true
      pagination keyset?: true, required?: false
    end

    read :mcp_list do
      pagination keyset?: true, required?: false

      prepare fn query, _context ->
        require Ash.Query

        case query.context[:spotter_mcp_scope] do
          %{project_id: project_id} when is_binary(project_id) ->
            Ash.Query.filter(query, project_id == ^project_id)

          _ ->
            Ash.Query.add_error(query, "MCP project scope is required but missing or invalid")
        end
      end
    end

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
        :project_id,
        :custom_title,
        :summary,
        :first_prompt,
        :source_created_at,
        :source_modified_at,
        :hook_ended_at
      ]
    end

    update :update do
      primary? true

      accept [
        :slug,
        :transcript_dir,
        :cwd,
        :git_branch,
        :version,
        :started_at,
        :ended_at,
        :schema_version,
        :message_count,
        :custom_title,
        :summary,
        :first_prompt,
        :source_created_at,
        :source_modified_at,
        :distilled_summary,
        :distilled_status,
        :distilled_model_used,
        :distilled_at,
        :hook_ended_at
      ]

      require_atomic? false
    end

    update :hide do
      accept []
      change set_attribute(:hidden_at, &DateTime.utc_now/0)
    end

    update :unhide do
      accept []
      change set_attribute(:hidden_at, nil)
    end

    update :add_line_stats do
      accept []

      argument :added_delta, :integer do
        allow_nil? false
      end

      argument :removed_delta, :integer do
        allow_nil? false
      end

      change atomic_update(:lines_added, expr(lines_added + ^arg(:added_delta)))
      change atomic_update(:lines_removed, expr(lines_removed + ^arg(:removed_delta)))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :session_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :slug, :string
    attribute :transcript_dir, :string
    attribute :cwd, :string
    attribute :git_branch, :string, public?: true
    attribute :version, :string

    attribute :started_at, :utc_datetime_usec, public?: true
    attribute :ended_at, :utc_datetime_usec, public?: true

    attribute :schema_version, :integer do
      allow_nil? false
      default 1
    end

    attribute :message_count, :integer, public?: true
    attribute :hidden_at, :utc_datetime_usec, allow_nil?: true

    attribute :custom_title, :string
    attribute :summary, :string
    attribute :first_prompt, :string
    attribute :source_created_at, :utc_datetime_usec
    attribute :source_modified_at, :utc_datetime_usec

    attribute :lines_added, :integer do
      allow_nil? false
      default 0
    end

    attribute :lines_removed, :integer do
      allow_nil? false
      default 0
    end

    attribute :distilled_summary, :string
    attribute :distilled_model_used, :string
    attribute :distilled_at, :utc_datetime_usec
    attribute :hook_ended_at, :utc_datetime_usec

    attribute :distilled_status, :atom do
      constraints one_of: [:pending, :skipped, :completed, :error]
      default :pending
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
      attribute_public? true
    end

    has_many :messages, Spotter.Transcripts.Message
    has_many :subagents, Spotter.Transcripts.Subagent
    has_many :annotations, Spotter.Transcripts.Annotation
    has_many :tool_calls, Spotter.Transcripts.ToolCall
    has_many :session_reworks, Spotter.Transcripts.SessionRework
  end

  identities do
    identity :unique_session_id, [:session_id]
  end
end
