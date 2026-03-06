defmodule Spotter.Transcripts.SessionsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Test.OtelHelpers
  alias Spotter.Transcripts.{Project, Session, Sessions}

  require Ash.Query

  setup do
    :ok = Sandbox.checkout(Spotter.Repo)
    Sandbox.mode(Spotter.Repo, {:shared, self()})
    OtelHelpers.setup_otel_test(%{})
    :ok
  end

  defp create_project!(name, pattern) do
    Ash.create!(Project, %{name: name, pattern: pattern})
  end

  describe "find_or_create/2 with worktree cwd canonicalization" do
    test "worktree cwd auto-creates project from canonical repo root, not worktree leaf" do
      # No pre-existing project — auto-creation should use canonical repo root
      session_id = Ash.UUID.generate()
      worktree_cwd = "/home/marco/projects/spotter/.claude/worktrees/my-feature"

      {:ok, session} = Sessions.find_or_create(session_id, cwd: worktree_cwd)

      project = Project |> Ash.Query.filter(id == ^session.project_id) |> Ash.read_one!()
      assert project.name == "spotter"

      # TELEMETRY: canonicalize_cwd span emitted with correct attributes
      assert OtelHelpers.assert_span_attributes("spotter.sessions.canonicalize_cwd", %{
               "spotter.sessions.original_cwd" => worktree_cwd,
               "spotter.sessions.canonical_cwd" => "/home/marco/projects/spotter",
               "spotter.sessions.cwd_changed" => true
             })
    end

    test "non-git directory falls back to original cwd for project creation" do
      # Create a temp dir that is NOT a git repo
      tmp_base = System.tmp_dir!()
      non_git_dir = Path.join(tmp_base, "not-a-repo-#{System.unique_integer([:positive])}")
      File.mkdir_p!(non_git_dir)

      on_exit(fn -> File.rm_rf!(non_git_dir) end)

      # canonicalize_cwd should return the original path unchanged
      assert Sessions.canonicalize_cwd(non_git_dir) == non_git_dir
    end

    test "stale worktree path (non-existent dir) falls back via path heuristic" do
      # Simulates a worktree dir that was deleted but still referenced
      stale_cwd = "/home/marco/projects/spotter/.claude/worktrees/deleted-branch"

      # Directory doesn't exist on disk, so git can't run
      # Path heuristic should still strip .claude/worktrees/<name>
      assert Sessions.canonicalize_cwd(stale_cwd) == "/home/marco/projects/spotter"
    end

    test "normal repo cwd (non-worktree) is not changed by canonicalization" do
      # Use a known non-worktree git repo — derive main repo from git
      {main_repo, 0} =
        System.cmd("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"],
          cd: Path.expand("../../..", __DIR__)
        )

      main_repo = main_repo |> String.trim() |> Path.dirname()
      canonical = Sessions.canonicalize_cwd(main_repo)

      # For a normal git repo root, canonicalize should return the same path
      assert canonical == main_repo

      # TELEMETRY: cwd_changed should be false for non-worktree repos
      assert OtelHelpers.assert_span_attributes("spotter.sessions.canonicalize_cwd", %{
               "spotter.sessions.cwd_changed" => false
             })
    end
  end

  describe "find_or_create/2 with overlapping project patterns" do
    test "resolves todo2 correctly when todo pattern also matches" do
      create_project!("todo", "^-home-marco-projects-todo")
      create_project!("todo2", "^-home-marco-projects-todo2")

      session_id = Ash.UUID.generate()
      {:ok, session} = Sessions.find_or_create(session_id, cwd: "/home/marco/projects/todo2")

      project = Project |> Ash.Query.filter(id == ^session.project_id) |> Ash.read_one!()
      assert project.name == "todo2"
    end

    test "resolves todo correctly when todo2 pattern does not match" do
      create_project!("todo", "^-home-marco-projects-todo")
      create_project!("todo2", "^-home-marco-projects-todo2")

      session_id = Ash.UUID.generate()
      {:ok, session} = Sessions.find_or_create(session_id, cwd: "/home/marco/projects/todo")

      project = Project |> Ash.Query.filter(id == ^session.project_id) |> Ash.read_one!()
      assert project.name == "todo"
    end

    test "longest pattern wins regardless of insertion order" do
      # Insert the more specific pattern first
      create_project!("todo2", "^-home-marco-projects-todo2")
      create_project!("todo", "^-home-marco-projects-todo")

      session_id = Ash.UUID.generate()
      {:ok, session} = Sessions.find_or_create(session_id, cwd: "/home/marco/projects/todo2")

      project = Project |> Ash.Query.filter(id == ^session.project_id) |> Ash.read_one!()
      assert project.name == "todo2"
    end

    test "auto-creates project when no pattern matches" do
      create_project!("todo", "^-home-marco-projects-todo")

      session_id = Ash.UUID.generate()
      {:ok, session} = Sessions.find_or_create(session_id, cwd: "/home/marco/projects/unrelated")

      project = Project |> Ash.Query.filter(id == ^session.project_id) |> Ash.read_one!()
      assert project.name == "unrelated"
      assert project.pattern == "^\\-home\\-marco\\-projects\\-unrelated$"
    end

    test "auto-created project is reused on subsequent sessions" do
      cwd = "/home/marco/projects/newapp"

      {:ok, session1} = Sessions.find_or_create(Ash.UUID.generate(), cwd: cwd)
      {:ok, session2} = Sessions.find_or_create(Ash.UUID.generate(), cwd: cwd)

      assert session1.project_id == session2.project_id
    end

    test "returns error when cwd is nil" do
      session_id = Ash.UUID.generate()
      assert {:error, :project_not_found} = Sessions.find_or_create(session_id)
    end

    test "single matching pattern is selected without ambiguity" do
      create_project!("spotter", "^-home-marco-projects-spotter")
      create_project!("todo", "^-home-marco-projects-todo")

      session_id = Ash.UUID.generate()
      {:ok, session} = Sessions.find_or_create(session_id, cwd: "/home/marco/projects/spotter")

      project = Project |> Ash.Query.filter(id == ^session.project_id) |> Ash.read_one!()
      assert project.name == "spotter"
    end

    test "deeply nested path resolves to most specific pattern" do
      create_project!("app", "^-home-marco-projects-app")
      create_project!("app-mobile", "^-home-marco-projects-app-mobile")

      session_id = Ash.UUID.generate()

      {:ok, session} =
        Sessions.find_or_create(session_id, cwd: "/home/marco/projects/app-mobile")

      project = Project |> Ash.Query.filter(id == ^session.project_id) |> Ash.read_one!()
      assert project.name == "app-mobile"
    end
  end

  describe "ended_at vs session_ended_at semantics" do
    test "ended_at alone does not mark session as hook-finished" do
      project = create_project!("ended-at-test", "^ended-at-test$")
      session_id = Ash.UUID.generate()

      session =
        Ash.create!(Session, %{
          session_id: session_id,
          project_id: project.id,
          cwd: "/home/user/ended-at-test",
          ended_at: DateTime.utc_now()
        })

      assert session.ended_at != nil
      assert session.session_ended_at == nil
    end
  end

  describe "hook_ended_at removal" do
    test "no runtime references to hook_ended_at remain in lib/" do
      {output, 0} =
        System.cmd("grep", [
          "-r",
          "--include=*.ex",
          "-l",
          "hook_ended_at",
          Path.expand("../../../lib", __DIR__)
        ])
        |> case do
          {output, 0} -> {output, 0}
          {_, 1} -> {"", 0}
          other -> other
        end

      files = output |> String.trim() |> String.split("\n", trim: true)

      assert files == [],
             "Expected no runtime references to hook_ended_at in lib/, found: #{Enum.join(files, ", ")}"
    end
  end
end
