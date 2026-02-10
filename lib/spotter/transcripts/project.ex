defmodule Spotter.Transcripts.Project do
  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "projects"
    repo Spotter.Repo
  end

  json_api do
    type "project"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :pattern]
    end

    update :update do
      primary? true
      accept [:name, :pattern]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      allow_nil? false
    end

    attribute :pattern, :string do
      allow_nil? false
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :sessions, Spotter.Transcripts.Session
  end

  identities do
    identity :unique_name, [:name]
  end
end
