defmodule Spotter.Transcripts.SessionSlice do
  @moduledoc "A saved slice of a session transcript, highlighting specific tool uses with context."
  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "session_slices"
    repo Spotter.Repo
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      accept [
        :session_id,
        :project_id,
        :title,
        :filters,
        :highlight_tool_use_ids,
        :context_before_lines,
        :context_after_lines
      ]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :title, :string do
      allow_nil? true
      public? true
    end

    attribute :filters, :map do
      default %{}
      public? true
    end

    attribute :highlight_tool_use_ids, {:array, :string} do
      default []
      public? true
    end

    attribute :context_before_lines, :integer do
      default 5
      public? true
    end

    attribute :context_after_lines, :integer do
      default 5
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end

    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end
  end
end
