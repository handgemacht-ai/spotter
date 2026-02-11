defmodule Spotter.Transcripts.AnnotationMessageRef do
  @moduledoc false
  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "annotation_message_refs"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:annotation_id, :message_id, :ordinal]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :ordinal, :integer, allow_nil?: false

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :annotation, Spotter.Transcripts.Annotation do
      allow_nil? false
    end

    belongs_to :message, Spotter.Transcripts.Message do
      allow_nil? false
    end
  end

  identities do
    identity :unique_annotation_message, [:annotation_id, :message_id]
  end
end
