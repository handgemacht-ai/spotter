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

      base_route "/file_snapshots", Spotter.Transcripts.FileSnapshot do
        get :read
        index :read
      end

      base_route "/tool_calls", Spotter.Transcripts.ToolCall do
        get :read
        index :read
      end

      base_route "/commits", Spotter.Transcripts.Commit do
        get :read
        index :read
      end

      base_route "/session_commit_links", Spotter.Transcripts.SessionCommitLink do
        get :read
        index :read
      end

      base_route "/file_heatmaps", Spotter.Transcripts.FileHeatmap do
        get :read
        index :read
      end

      base_route "/session_reworks", Spotter.Transcripts.SessionRework do
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
    resource Spotter.Transcripts.AnnotationMessageRef
    resource Spotter.Transcripts.FileSnapshot
    resource Spotter.Transcripts.ToolCall
    resource Spotter.Transcripts.Commit
    resource Spotter.Transcripts.SessionCommitLink
    resource Spotter.Transcripts.FileHeatmap
    resource Spotter.Transcripts.SessionRework
  end
end
