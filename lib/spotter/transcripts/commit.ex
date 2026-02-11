defmodule Spotter.Transcripts.Commit do
  @moduledoc "A Git commit captured during a Claude Code session."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "commits"
    repo Spotter.Repo
  end

  json_api do
    type "commit"
  end

  actions do
    defaults [:read, :destroy]

    update :update do
      primary? true

      accept [
        :parent_hashes,
        :git_branch,
        :subject,
        :body,
        :author_name,
        :author_email,
        :authored_at,
        :committed_at,
        :patch_id_stable,
        :changed_files
      ]
    end

    create :create do
      primary? true

      accept [
        :commit_hash,
        :parent_hashes,
        :git_branch,
        :subject,
        :body,
        :author_name,
        :author_email,
        :authored_at,
        :committed_at,
        :patch_id_stable,
        :changed_files
      ]

      upsert? true
      upsert_identity :unique_commit_hash
      upsert_fields []
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :commit_hash, :string, allow_nil?: false
    attribute :parent_hashes, {:array, :string}, allow_nil?: false, default: []
    attribute :git_branch, :string
    attribute :subject, :string
    attribute :body, :string
    attribute :author_name, :string
    attribute :author_email, :string
    attribute :authored_at, :utc_datetime_usec
    attribute :committed_at, :utc_datetime_usec
    attribute :patch_id_stable, :string
    attribute :changed_files, {:array, :string}, allow_nil?: false, default: []

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_commit_hash, [:commit_hash]
  end
end
