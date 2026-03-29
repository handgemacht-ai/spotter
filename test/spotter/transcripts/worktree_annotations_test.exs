defmodule Spotter.Transcripts.WorktreeAnnotationsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Test.OtelHelpers
  alias Spotter.Transcripts.{Annotation, Project, Sessions}

  require Ash.Query

  setup do
    :ok = Sandbox.checkout(Spotter.Repo)
    Sandbox.mode(Spotter.Repo, {:shared, self()})
    OtelHelpers.setup_otel_test(%{})
    :ok
  end

  describe "resolve_project_by_cwd with worktree paths" do
    test "resolves worktree path to canonical project" do
      main_cwd = "/home/test/projects/myapp"
      {:ok, session} = Sessions.find_or_create(Ash.UUID.generate(), cwd: main_cwd)
      project = Ash.get!(Project, session.project_id)

      worktree_cwd = "/home/test/projects/myapp/.claude/worktrees/feat-branch"
      assert {:ok, resolved} = Sessions.resolve_project_by_cwd(worktree_cwd)
      assert resolved.id == project.id
    end

    test "returns error for unknown path" do
      assert {:error, {:project_not_found, _}} =
               Sessions.resolve_project_by_cwd("/nonexistent/path")
    end

    test "prefers subdirectory project over git-root project in monorepo" do
      parent_cwd = "/home/test/monorepo"
      sub_cwd = "/home/test/monorepo/subproject"

      {:ok, _parent_session} = Sessions.find_or_create(Ash.UUID.generate(), cwd: parent_cwd)
      {:ok, sub_session} = Sessions.find_or_create(Ash.UUID.generate(), cwd: sub_cwd)
      sub_project = Ash.get!(Project, sub_session.project_id)

      assert {:ok, resolved} = Sessions.resolve_project_by_cwd(sub_cwd)
      assert resolved.id == sub_project.id
      assert resolved.name == "subproject"
    end
  end

  describe "extract_worktree_name/2" do
    test "returns nil for identical paths" do
      assert nil == Sessions.extract_worktree_name("/home/test/myapp", "/home/test/myapp")
    end

    test "returns nil for identical paths with trailing slash" do
      assert nil == Sessions.extract_worktree_name("/home/test/myapp/", "/home/test/myapp")
    end

    test "returns basename for worktree path" do
      assert "feat-branch" ==
               Sessions.extract_worktree_name(
                 "/home/test/myapp/.claude/worktrees/feat-branch",
                 "/home/test/myapp"
               )
    end

    test "returns basename for gtr-style worktree" do
      assert "myapp-feature" ==
               Sessions.extract_worktree_name(
                 "/home/test/projects/myapp-feature",
                 "/home/test/projects/myapp"
               )
    end

    test "returns nil for nil inputs" do
      assert nil == Sessions.extract_worktree_name(nil, "/some/path")
      assert nil == Sessions.extract_worktree_name("/some/path", nil)
    end
  end

  describe "MCP annotation worktree filtering" do
    setup do
      main_cwd = "/home/test/projects/testapp"
      {:ok, session} = Sessions.find_or_create(Ash.UUID.generate(), cwd: main_cwd)
      project = Ash.get!(Project, session.project_id)

      main_ann =
        Ash.create!(Annotation, %{
          source: :file,
          selected_text: "main annotation",
          comment: "from main",
          project_id: project.id,
          metadata: %{}
        })

      wt_ann =
        Ash.create!(Annotation, %{
          source: :file,
          selected_text: "worktree annotation",
          comment: "from worktree",
          project_id: project.id,
          metadata: %{"worktree_name" => "feat-branch"}
        })

      other_wt_ann =
        Ash.create!(Annotation, %{
          source: :file,
          selected_text: "other worktree annotation",
          comment: "from other worktree",
          project_id: project.id,
          metadata: %{"worktree_name" => "fix-bug"}
        })

      %{
        project: project,
        main_ann: main_ann,
        wt_ann: wt_ann,
        other_wt_ann: other_wt_ann
      }
    end

    test "from main checkout returns all annotations", ctx do
      scope = %{project_id: ctx.project.id, worktree_name: nil}

      results =
        Annotation
        |> Ash.Query.for_read(:mcp_read_review_annotations, %{},
          context: %{spotter_mcp_scope: scope}
        )
        |> Ash.read!()

      ids = Enum.map(results, & &1.id) |> MapSet.new()
      assert MapSet.member?(ids, ctx.main_ann.id)
      assert MapSet.member?(ids, ctx.wt_ann.id)
      assert MapSet.member?(ids, ctx.other_wt_ann.id)
    end

    test "from worktree returns own + main annotations", ctx do
      scope = %{project_id: ctx.project.id, worktree_name: "feat-branch"}

      results =
        Annotation
        |> Ash.Query.for_read(:mcp_read_review_annotations, %{},
          context: %{spotter_mcp_scope: scope}
        )
        |> Ash.read!()

      ids = Enum.map(results, & &1.id) |> MapSet.new()
      assert MapSet.member?(ids, ctx.main_ann.id)
      assert MapSet.member?(ids, ctx.wt_ann.id)
      refute MapSet.member?(ids, ctx.other_wt_ann.id)
    end
  end
end
