defmodule Spotter.Transcripts.Jobs.IngestRecentCommitsTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Commit, Project, ReviewItem, Session}
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

      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          project_id: project.id,
          cwd: cwd,
          started_at: DateTime.utc_now()
        })

      %{project: project, session: session}
    end

    test "ingests commits and creates review items", %{project: project} do
      job = %Oban.Job{args: %{"project_id" => project.id, "limit" => 3}}
      assert :ok = IngestRecentCommits.perform(job)

      commits = Ash.read!(Commit)
      assert commits != []

      review_items = Ash.read!(ReviewItem)
      assert review_items != []

      # Each commit should have a review item
      commit_ids = MapSet.new(commits, & &1.id)

      Enum.each(review_items, fn ri ->
        assert ri.target_kind == :commit_message
        assert ri.importance == :medium
        assert ri.next_due_on == Date.utc_today()
        assert MapSet.member?(commit_ids, ri.commit_id)
      end)
    end

    test "enqueued jobs include run_id in args", %{project: project} do
      job = %Oban.Job{args: %{"project_id" => project.id, "limit" => 1}}
      assert :ok = IngestRecentCommits.perform(job)

      enqueued_jobs =
        Repo.all(
          from(j in Oban.Job,
            where:
              j.worker in [
                "Spotter.Transcripts.Jobs.AnalyzeCommitHotspots",
                "Spotter.Transcripts.Jobs.AnalyzeCommitTests",
                "Spotter.ProductSpec.Jobs.UpdateRollingSpec"
              ]
          )
        )

      assert enqueued_jobs != [], "expected at least one downstream job to be enqueued"

      Enum.each(enqueued_jobs, fn j ->
        assert is_binary(j.args["run_id"]),
               "expected run_id in #{j.worker} args, got: #{inspect(j.args)}"

        assert j.args["project_id"] == project.id
        assert is_binary(j.args["commit_hash"])
      end)
    end
  end
end
