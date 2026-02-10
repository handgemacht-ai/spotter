defmodule Spotter.Transcripts do
  @moduledoc "Domain for indexing and querying Claude Code session transcripts."
  use Ash.Domain,
    extensions: [
      AshJsonApi.Domain
    ]

  json_api do
    routes do
      base_route "/projects", Spotter.Transcripts.Project do
        get :read
        index :read
      end

      base_route "/sessions", Spotter.Transcripts.Session do
        get :read
        index :read
      end

      base_route "/messages", Spotter.Transcripts.Message do
        get :read
        index :read
      end

      base_route "/subagents", Spotter.Transcripts.Subagent do
        get :read
        index :read
      end
    end
  end

  resources do
    resource Spotter.Transcripts.Project
    resource Spotter.Transcripts.Session
    resource Spotter.Transcripts.Message
    resource Spotter.Transcripts.Subagent
    resource Spotter.Transcripts.Annotation
  end
end
