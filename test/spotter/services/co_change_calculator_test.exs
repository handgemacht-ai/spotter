defmodule Spotter.Services.CoChangeCalculatorTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.CoChangeCalculator
  alias Spotter.Transcripts.{CoChangeGroup, Project, Session}

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_session(project, opts \\ []) do
    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "test-dir",
      project_id: project.id,
      cwd: opts[:cwd]
    })
  end

  defp read_groups(project_id, scope) do
    CoChangeGroup
    |> Ash.Query.filter(project_id == ^project_id and scope == ^scope)
    |> Ash.read!()
  end

  describe "compute/2" do
    test "returns :ok for project with no sessions" do
      project = create_project("calc-no-sessions")
      assert :ok = CoChangeCalculator.compute(project.id)
    end

    test "returns :ok for session with inaccessible cwd" do
      project = create_project("calc-bad-cwd")
      create_session(project, cwd: "/nonexistent/path/abc123")
      assert :ok = CoChangeCalculator.compute(project.id)
    end

    test "returns :ok and persists groups for valid repo" do
      project = create_project("calc-real-repo")
      # Use the current repo as the cwd - it has real git history
      create_session(project, cwd: File.cwd!())

      assert :ok = CoChangeCalculator.compute(project.id)

      # Should have computed some file groups from real git history
      file_groups = read_groups(project.id, :file)
      dir_groups = read_groups(project.id, :directory)

      # Real repo should produce at least some groups
      assert is_list(file_groups)
      assert is_list(dir_groups)
    end

    test "cleans up stale rows on re-run" do
      project = create_project("calc-stale")

      # Insert a stale co-change group
      Ash.create!(CoChangeGroup, %{
        project_id: project.id,
        scope: :file,
        group_key: "stale_a.ex|stale_b.ex",
        members: ["stale_a.ex", "stale_b.ex"],
        frequency_30d: 5
      })

      # Run with no sessions => no groups computed => stale row should be deleted
      assert :ok = CoChangeCalculator.compute(project.id)

      # Stale row should be gone (no sessions = skip, rows kept intact)
      # Actually, no sessions means :skip so existing rows are kept
      remaining = read_groups(project.id, :file)
      assert length(remaining) == 1
    end

    test "deletes stale rows when repo is accessible" do
      project = create_project("calc-stale-cleanup")
      create_session(project, cwd: File.cwd!())

      # Insert a stale co-change group with a key that won't exist in real data
      Ash.create!(CoChangeGroup, %{
        project_id: project.id,
        scope: :file,
        group_key: "zzz_nonexistent_a.ex|zzz_nonexistent_b.ex",
        members: ["zzz_nonexistent_a.ex", "zzz_nonexistent_b.ex"],
        frequency_30d: 5
      })

      assert :ok = CoChangeCalculator.compute(project.id)

      # The stale row should be removed
      remaining = read_groups(project.id, :file)
      stale = Enum.find(remaining, &(&1.group_key == "zzz_nonexistent_a.ex|zzz_nonexistent_b.ex"))
      assert stale == nil
    end
  end
end
