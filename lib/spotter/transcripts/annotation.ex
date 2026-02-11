defmodule Spotter.Transcripts.Annotation do
  @moduledoc false
  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "annotations"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :session_id,
        :selected_text,
        :start_row,
        :start_col,
        :end_row,
        :end_col,
        :comment,
        :source
      ]
    end

    update :update do
      primary? true
      accept [:comment]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :source, :atom do
      allow_nil? false
      default :terminal
      constraints one_of: [:terminal, :transcript]
    end

    attribute :selected_text, :string, allow_nil?: false
    attribute :start_row, :integer, allow_nil?: true
    attribute :start_col, :integer, allow_nil?: true
    attribute :end_row, :integer, allow_nil?: true
    attribute :end_col, :integer, allow_nil?: true
    attribute :comment, :string, allow_nil?: false

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end

    has_many :message_refs, Spotter.Transcripts.AnnotationMessageRef
  end
end
