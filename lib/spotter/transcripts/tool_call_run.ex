defmodule Spotter.Transcripts.ToolCallRun do
  @moduledoc "A paired tool-use/tool-result run derived from session messages."
  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "tool_call_runs"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :tool_use_id,
        :tool_name,
        :command,
        :command_fingerprint,
        :input_summary,
        :tool_input,
        :status,
        :started_at,
        :finished_at,
        :duration_ms,
        :duration_source,
        :start_ordinal,
        :end_ordinal,
        :source_scope,
        :agent_id,
        :subagent_id,
        :parent_tool_use_id,
        :worktree_name,
        :canonical_cwd,
        :session_id,
        :project_id,
        :error_content
      ]

      change fn changeset, _context ->
        changeset
        |> maybe_derive_duration()
      end
    end

    create :upsert do
      accept [
        :tool_use_id,
        :tool_name,
        :command,
        :command_fingerprint,
        :input_summary,
        :tool_input,
        :status,
        :started_at,
        :finished_at,
        :duration_ms,
        :duration_source,
        :start_ordinal,
        :end_ordinal,
        :source_scope,
        :agent_id,
        :subagent_id,
        :parent_tool_use_id,
        :worktree_name,
        :canonical_cwd,
        :session_id,
        :project_id,
        :error_content
      ]

      upsert? true
      upsert_identity :unique_tool_use_id

      upsert_fields [
        :tool_name,
        :command,
        :command_fingerprint,
        :input_summary,
        :tool_input,
        :status,
        :started_at,
        :finished_at,
        :duration_ms,
        :duration_source,
        :start_ordinal,
        :end_ordinal,
        :source_scope,
        :agent_id,
        :subagent_id,
        :parent_tool_use_id,
        :worktree_name,
        :canonical_cwd,
        :error_content
      ]

      change fn changeset, _context ->
        changeset
        |> maybe_derive_duration()
      end
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :tool_use_id, :string, allow_nil?: false
    attribute :tool_name, :string, allow_nil?: false
    attribute :command, :string
    attribute :command_fingerprint, :string
    attribute :input_summary, :string

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:completed, :error, :ongoing, :orphan]
      default :ongoing
    end

    attribute :started_at, :utc_datetime_usec
    attribute :finished_at, :utc_datetime_usec
    attribute :duration_ms, :integer

    attribute :duration_source, :atom do
      constraints one_of: [:explicit, :timestamp_derived, :unavailable]
    end

    attribute :start_ordinal, :integer
    attribute :end_ordinal, :integer
    attribute :source_scope, :string
    attribute :agent_id, :string
    attribute :subagent_id, :string
    attribute :parent_tool_use_id, :string
    attribute :worktree_name, :string
    attribute :canonical_cwd, :string
    attribute :error_content, :string
    attribute :tool_input, :map

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end

    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end
  end

  calculations do
    calculate :ingest_status, :atom, expr(session.ingest_status)
  end

  identities do
    identity :unique_tool_use_id, [:tool_use_id]
  end

  defp maybe_derive_duration(changeset) do
    duration = Ash.Changeset.get_attribute(changeset, :duration_ms)
    started = Ash.Changeset.get_attribute(changeset, :started_at)
    finished = Ash.Changeset.get_attribute(changeset, :finished_at)

    cond do
      duration != nil ->
        Ash.Changeset.force_change_attribute(changeset, :duration_source, :explicit)

      started != nil && finished != nil ->
        derived = DateTime.diff(finished, started, :millisecond)

        changeset
        |> Ash.Changeset.force_change_attribute(:duration_ms, derived)
        |> Ash.Changeset.force_change_attribute(:duration_source, :timestamp_derived)

      true ->
        Ash.Changeset.force_change_attribute(changeset, :duration_source, :unavailable)
    end
  end
end
