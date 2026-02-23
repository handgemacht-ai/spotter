defmodule Spotter.Transcripts.Team do
  @moduledoc "A team within a project, grouping related agent sessions."
  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "teams"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :project_id]
      upsert? true
      upsert_identity :unique_team_per_project
      upsert_fields []
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
      attribute_public? true
    end

    has_many :team_members, Spotter.Transcripts.TeamMember
  end

  identities do
    identity :unique_team_per_project, [:project_id, :name]
  end
end
