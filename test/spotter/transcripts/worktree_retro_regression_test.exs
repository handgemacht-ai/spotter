defmodule Spotter.Transcripts.WorktreeRetroRegressionTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Test.OtelHelpers
  alias Spotter.Transcripts.{Project, RetroSubmission, Sessions}

  require Ash.Query

  setup do
    :ok = Sandbox.checkout(Spotter.Repo)
    Sandbox.mode(Spotter.Repo, {:shared, self()})
    OtelHelpers.setup_otel_test(%{})
    :ok
  end

  describe "worktree retro regression" do
    test "worktree session start assigns canonical project" do
      session_id = Ash.UUID.generate()
      worktree_cwd = "/home/test/projects/myapp/.claude/worktrees/my-feature"

      {:ok, session} = Sessions.find_or_create(session_id, cwd: worktree_cwd)

      project = Ash.get!(Project, session.project_id)
      assert project.name == "myapp"
    end

    test "MCP retro submission for worktree session scopes to canonical project" do
      session_id = Ash.UUID.generate()
      worktree_cwd = "/home/test/projects/myapp/.claude/worktrees/add-tests"

      {:ok, session} = Sessions.find_or_create(session_id, cwd: worktree_cwd)
      project = Ash.get!(Project, session.project_id)

      submission =
        Ash.create!(
          RetroSubmission,
          %{
            session_id: session.session_id,
            items: [
              %{
                "category" => "knowledge_gained",
                "observation" => "Worktree retro scoping works",
                "explanation" => "Submission lands on canonical project"
              }
            ]
          },
          action: :mcp_submit,
          context: %{spotter_mcp_scope: %{project_id: project.id}}
        )

      assert submission.project_id == project.id
    end

    test "retro item from worktree session traverses to correct session" do
      session_id = Ash.UUID.generate()
      worktree_cwd = "/home/test/projects/myapp/.claude/worktrees/traversal-check"

      {:ok, session} = Sessions.find_or_create(session_id, cwd: worktree_cwd)
      project = Ash.get!(Project, session.project_id)

      submission =
        Ash.create!(
          RetroSubmission,
          %{
            session_id: session.session_id,
            items: [
              %{
                "category" => "gotcha",
                "observation" => "Item traversal test",
                "explanation" => "Verifies item -> session chain"
              }
            ]
          },
          action: :mcp_submit,
          context: %{spotter_mcp_scope: %{project_id: project.id}}
        )

      item = submission |> Ash.load!(:items) |> Map.get(:items) |> hd()
      loaded = Ash.load!(item, :session)

      assert loaded.session.id == session.id
      assert loaded.session.project_id == project.id
    end

    test "worktree and main-repo sessions share same canonical project" do
      id1 = Ash.UUID.generate()
      id2 = Ash.UUID.generate()

      {:ok, wt_session} =
        Sessions.find_or_create(id1,
          cwd: "/home/test/projects/myapp/.claude/worktrees/feat"
        )

      {:ok, main_session} =
        Sessions.find_or_create(id2, cwd: "/home/test/projects/myapp")

      assert wt_session.project_id == main_session.project_id
    end

    test "MCP retro rejects cross-project session reference" do
      session_id = Ash.UUID.generate()

      {:ok, session} =
        Sessions.find_or_create(session_id,
          cwd: "/home/test/projects/myapp/.claude/worktrees/cross-proj"
        )

      other_project =
        Ash.create!(Project, %{name: "other-project", pattern: "^other-project$"})

      # Session belongs to "myapp", but MCP scope says "other-project" — must reject
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(
          RetroSubmission,
          %{
            session_id: session.session_id,
            items: [
              %{
                "category" => "struggle",
                "observation" => "Cross-project attempt",
                "explanation" => "Should be rejected"
              }
            ]
          },
          action: :mcp_submit,
          context: %{spotter_mcp_scope: %{project_id: other_project.id}}
        )
      end
    end
  end
end
