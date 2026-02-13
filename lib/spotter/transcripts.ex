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

      base_route "/co_change_groups", Spotter.Transcripts.CoChangeGroup do
        get :read
        index :read
      end

      base_route "/co_change_group_commits", Spotter.Transcripts.CoChangeGroupCommit do
        get :read
        index :read
      end

      base_route "/co_change_group_member_stats", Spotter.Transcripts.CoChangeGroupMemberStat do
        get :read
        index :read
      end

      base_route "/commit_hotspots", Spotter.Transcripts.CommitHotspot do
        get :read
        index :read
      end

      base_route "/commit_hotspots", Spotter.Transcripts.CommitHotspot do
        get :read
        index :read
      end

      base_route "/prompt_pattern_runs", Spotter.Transcripts.PromptPatternRun do
        get :read
        index :read
      end

      base_route "/prompt_patterns", Spotter.Transcripts.PromptPattern do
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
    resource Spotter.Transcripts.CoChangeGroup
    resource Spotter.Transcripts.CoChangeGroupCommit
    resource Spotter.Transcripts.CoChangeGroupMemberStat
    resource Spotter.Transcripts.CommitHotspot
    resource Spotter.Transcripts.CommitFile
    resource Spotter.Transcripts.AnnotationFileRef
    resource Spotter.Transcripts.CommitHotspot
    resource Spotter.Transcripts.ReviewItem
    resource Spotter.Transcripts.ProjectIngestState
    resource Spotter.Transcripts.PromptPatternRun
    resource Spotter.Transcripts.PromptPattern
    resource Spotter.Transcripts.SessionDistillation
    resource Spotter.Transcripts.ProjectPeriodSummary
    resource Spotter.Transcripts.ProjectRollingSummary
    resource Spotter.ProductSpec.RollingSpecRun
  end
end
