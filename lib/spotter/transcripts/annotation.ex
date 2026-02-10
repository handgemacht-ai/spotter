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
      accept [:pane_id, :selected_text, :start_row, :start_col, :end_row, :end_col, :comment]
    end

    update :update do
      primary? true
      accept [:comment]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :pane_id, :string, allow_nil?: false
    attribute :selected_text, :string, allow_nil?: false
    attribute :start_row, :integer, allow_nil?: false
    attribute :start_col, :integer, allow_nil?: false
    attribute :end_row, :integer, allow_nil?: false
    attribute :end_col, :integer, allow_nil?: false
    attribute :comment, :string, allow_nil?: false

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
