defmodule Spotter.Transcripts.CommitTestRun do
  @moduledoc "Provenance and status for a per-commit test analysis run."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "commit_test_runs"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      argument :project_id, :uuid_v7, allow_nil?: false
      argument :commit_id, :uuid_v7, allow_nil?: false

      change manage_relationship(:project_id, :project, type: :append_and_remove)
      change manage_relationship(:commit_id, :commit, type: :append_and_remove)

      accept [:status]
    end

    update :mark_running do
      require_atomic? false

      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      require_atomic? false
      accept [:model_used, :input_stats, :output_stats, :dolt_commit_hash]

      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change set_attribute(:error, nil)
    end

    update :fail do
      require_atomic? false
      accept [:error]

      change set_attribute(:status, :error)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      default :queued
      constraints one_of: [:queued, :running, :completed, :error]
    end

    attribute :model_used, :string
    attribute :input_stats, :map, allow_nil?: false, default: %{}
    attribute :output_stats, :map, allow_nil?: false, default: %{}
    attribute :dolt_commit_hash, :string, constraints: [max_length: 64]
    attribute :error, :string

    attribute :started_at, :utc_datetime_usec
    attribute :completed_at, :utc_datetime_usec

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project, allow_nil?: false
    belongs_to :commit, Spotter.Transcripts.Commit, allow_nil?: false
  end

  identities do
    identity :unique_commit_test_run, [:project_id, :commit_id]
  end
end
