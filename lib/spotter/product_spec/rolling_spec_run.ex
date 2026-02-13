defmodule Spotter.ProductSpec.RollingSpecRun do
  @moduledoc "Tracks product spec update runs per commit for idempotence and traceability."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "product_spec_runs"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :project_id,
        :commit_hash,
        :status,
        :git_cwd,
        :git_branch,
        :dolt_commit_hash,
        :started_at,
        :finished_at,
        :error,
        :metadata
      ]

      upsert? true
      upsert_identity :unique_run_per_commit
      upsert_fields [:status, :git_cwd, :git_branch, :started_at]
    end

    update :mark_running do
      accept []
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :mark_ok do
      accept [:dolt_commit_hash, :metadata]
      change set_attribute(:status, :ok)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
      change set_attribute(:error, nil)
    end

    update :mark_error do
      accept [:error, :metadata]
      change set_attribute(:status, :error)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end

    update :mark_skipped do
      accept []
      change set_attribute(:status, :skipped)
      change set_attribute(:finished_at, &DateTime.utc_now/0)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :project_id, :uuid, allow_nil?: false
    attribute :commit_hash, :string, allow_nil?: false, constraints: [max_length: 40]

    attribute :status, :atom,
      allow_nil?: false,
      default: :pending,
      constraints: [one_of: [:pending, :running, :ok, :error, :skipped]]

    attribute :git_cwd, :string
    attribute :git_branch, :string
    attribute :dolt_commit_hash, :string, constraints: [max_length: 40]
    attribute :started_at, :utc_datetime_usec
    attribute :finished_at, :utc_datetime_usec
    attribute :error, :string
    attribute :metadata, :map, default: %{}

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_run_per_commit, [:project_id, :commit_hash]
  end
end
