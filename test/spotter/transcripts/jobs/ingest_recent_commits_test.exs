defmodule Spotter.Transcripts.Jobs.IngestRecentCommitsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Commit, Project, Session}
  alias Spotter.Transcripts.Jobs.IngestRecentCommits

  setup do
    Sandbox.checkout(Repo)
  end

  describe "perform/1 with no accessible cwd" do
    test "returns :ok without crashing" do
      project = Ash.create!(Project, %{name: "test-ingest", pattern: "^test"})

      job = %Oban.Job{args: %{"project_id" => project.id}}
      assert :ok = IngestRecentCommits.perform(job)
    end

    test "returns :ok when session has non-existent cwd" do
      project = Ash.create!(Project, %{name: "test-ingest-bad", pattern: "^test"})

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id,
        cwd: "/nonexistent/path/to/repo"
      })

      job = %Oban.Job{args: %{"project_id" => project.id}}
      assert :ok = IngestRecentCommits.perform(job)
    end
  end

  describe "perform/1 with valid repo" do
    setup do
      project = Ash.create!(Project, %{name: "test-ingest-real", pattern: "^test"})

      # Use the current repo as a real git repo
      cwd = File.cwd!()

      _session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id,
          cwd: cwd,
          started_at: DateTime.utc_now()
        })

      %{project: project}
    end

    test "ingests commits", %{project: project} do
      job = %Oban.Job{args: %{"project_id" => project.id, "limit" => 3}}
      assert :ok = IngestRecentCommits.perform(job)

      commits = Ash.read!(Commit)
      assert commits != []
    end
  end
end
