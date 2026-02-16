defmodule Spotter.Transcripts.SpecTestLink do
  @moduledoc "Optional many-to-many link between product requirement specs and extracted tests by commit."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "spec_test_links"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :commit_hash,
        :requirement_spec_key,
        :test_key,
        :confidence,
        :source,
        :metadata
      ]

      argument :project_id, :uuid_v7, allow_nil?: false
      change manage_relationship(:project_id, :project, type: :append_and_remove)

      upsert? true
      upsert_identity :unique_spec_test_link
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :commit_hash, :string do
      allow_nil? false
      constraints max_length: 40
    end

    attribute :requirement_spec_key, :string, allow_nil?: false
    attribute :test_key, :string, allow_nil?: false

    attribute :confidence, :float do
      allow_nil? false
      default 1.0
      constraints min: 0.0, max: 1.0
    end

    attribute :source, :atom do
      allow_nil? false
      default :agent
      constraints one_of: [:agent, :manual, :inferred]
    end

    attribute :metadata, :map, allow_nil?: false, default: %{}

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project, allow_nil?: false
  end

  identities do
    identity :unique_spec_test_link, [:project_id, :commit_hash, :requirement_spec_key, :test_key]
  end
end
