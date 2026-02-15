defmodule Spotter.Transcripts.Project do
  @moduledoc "A configured project whose transcripts are synced."
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
      accept [:name, :pattern, :timezone]
    end

    update :update do
      primary? true
      accept [:name, :pattern, :timezone]
      require_atomic? false
    end
  end

  validations do
    validate {Spotter.Transcripts.Project.TimezoneValidation, []}
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :pattern, :string do
      allow_nil? false
    end

    attribute :timezone, :string do
      allow_nil? false
      default "Etc/UTC"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :sessions, Spotter.Transcripts.Session
    has_many :annotations, Spotter.Transcripts.Annotation
  end

  calculations do
    calculate :session_count, :integer, {Spotter.Transcripts.Project.SessionCount, []} do
      public? true
    end

    calculate :open_review_annotation_count,
              :integer,
              {Spotter.Transcripts.Project.OpenReviewAnnotationCount, []} do
      public? true
    end
  end

  identities do
    identity :unique_name, [:name]
  end
end
