defmodule Spotter.ProductSpec.Jobs.UpdateRollingSpecTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.ProductSpec.Jobs.UpdateRollingSpec
  alias Spotter.ProductSpec.RollingSpecRun
  alias Spotter.Repo
  alias Spotter.Transcripts.{Commit, Project, Session, SessionCommitLink}

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  defp create_session(project_id, attrs \\ %{}) do
    session =
      Ash.create!(Session, %{session_id: Ash.UUID.generate(), project_id: project_id})

    if map_size(attrs) > 0, do: Ash.update!(session, attrs), else: session
  end

  describe "perform/1 idempotence" do
    test "skips when run already has status :ok" do
      project_id = Ash.UUID.generate()
      commit_hash = String.duplicate("b", 40)

      # Pre-create a successful run
      {:ok, _run} =
        Ash.create(RollingSpecRun, %{
          project_id: project_id,
          commit_hash: commit_hash,
          status: :ok,
          finished_at: DateTime.utc_now()
        })

      job = %Oban.Job{
        args: %{
          "project_id" => project_id,
          "commit_hash" => commit_hash
        }
      }

      assert :ok = UpdateRollingSpec.perform(job)

      run =
        RollingSpecRun
        |> Ash.Query.filter(project_id == ^project_id and commit_hash == ^commit_hash)
        |> Ash.read_one!()

      assert run.status in [:ok, :skipped]
    end
  end

  describe "load_linked_session_summaries/1" do
    test "returns summaries for sessions with completed distillation" do
      commit_hash = String.duplicate("c", 40)
      project = Ash.create!(Project, %{name: "test-proj", pattern: "^test"})
      commit = Ash.create!(Commit, %{commit_hash: commit_hash, subject: "feat: test"})

      session =
        create_session(project.id, %{
          distilled_status: :completed,
          distilled_summary: "Added login page with email/password auth",
          distilled_at: DateTime.utc_now()
        })

      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      summaries = UpdateRollingSpec.load_linked_session_summaries(commit_hash)

      assert length(summaries) == 1
      [summary] = summaries
      assert summary.session_id == session.session_id
      assert summary.distilled_status == :completed
      assert summary.distilled_summary == "Added login page with email/password auth"
    end

    test "excludes sessions with pending distillation" do
      commit_hash = String.duplicate("d", 40)
      project = Ash.create!(Project, %{name: "test-proj-2", pattern: "^test2"})
      commit = Ash.create!(Commit, %{commit_hash: commit_hash, subject: "chore: deps"})

      session = create_session(project.id)

      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      assert UpdateRollingSpec.load_linked_session_summaries(commit_hash) == []
    end

    test "returns empty list when no commit matches" do
      assert UpdateRollingSpec.load_linked_session_summaries(String.duplicate("e", 40)) == []
    end
  end
end
