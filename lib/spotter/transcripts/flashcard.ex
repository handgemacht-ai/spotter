defmodule Spotter.Transcripts.Flashcard do
  @moduledoc false

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "flashcards"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :project_id,
        :annotation_id,
        :question,
        :front_snippet,
        :answer,
        :references
      ]

      upsert? true
      upsert_identity :unique_flashcard_per_annotation
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :question, :string, allow_nil?: true
    attribute :front_snippet, :string, allow_nil?: false
    attribute :answer, :string, allow_nil?: false

    attribute :references, :map do
      allow_nil? false
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end

    belongs_to :annotation, Spotter.Transcripts.Annotation do
      allow_nil? false
    end
  end

  identities do
    identity :unique_flashcard_per_annotation, [:annotation_id]
  end
end
