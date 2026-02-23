defmodule Spotter.Transcripts.TeamMember do
  @moduledoc "A member (agent session) within a team."
  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "team_members"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:agent_name, :team_id, :session_id]
      upsert? true
      upsert_identity :unique_member_per_team
      upsert_fields [:agent_name]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :agent_name, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :team, Spotter.Transcripts.Team do
      allow_nil? false
    end

    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end
  end

  identities do
    identity :unique_member_per_team, [:team_id, :session_id]
  end
end
