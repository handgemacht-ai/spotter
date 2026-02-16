defmodule Spotter.Transcripts.PromptPatternMatch do
  @moduledoc "An individual prompt-to-pattern match linking a message to a detected pattern."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "prompt_pattern_matches"
    repo Spotter.Repo
  end

  json_api do
    type "prompt_pattern_match"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:pattern_id, :message_id, :session_id]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :pattern, Spotter.Transcripts.PromptPattern, allow_nil?: false
    belongs_to :message, Spotter.Transcripts.Message, allow_nil?: false
    belongs_to :session, Spotter.Transcripts.Session, allow_nil?: false
  end

  identities do
    identity :unique_pattern_message, [:pattern_id, :message_id]
  end
end
