defmodule Spotter.Transcripts.Jobs.DistillCompletedSessionTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  alias Spotter.Transcripts.{
    Commit,
    Project,
    Session,
    SessionCommitLink,
    SessionDistillation
  }

  alias Spotter.Transcripts.Jobs.DistillCompletedSession

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)

    previous = Application.get_env(:spotter, :session_distiller_adapter)

    Application.put_env(
      :spotter,
      :session_distiller_adapter,
      Spotter.Services.SessionDistiller.Stub
    )

    on_exit(fn -> Application.put_env(:spotter, :session_distiller_adapter, previous) end)

    project = Ash.create!(Project, %{name: "distill-test", pattern: "^distill"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test",
        cwd: "/home/user/distill-project",
        project_id: project.id,
        hook_ended_at: DateTime.utc_now()
      })

    %{project: project, session: session}
  end

  describe "session with commit links" do
    test "sets distilled_status to completed and stores distilled_summary", %{session: session} do
      commit =
        Ash.create!(Commit, %{
          commit_hash: "abc123def456",
          git_branch: "main",
          subject: "feat: add timezone support"
        })

      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      assert :ok =
               DistillCompletedSession.perform(%Oban.Job{
                 args: %{"session_id" => to_string(session.session_id)}
               })

      updated = Ash.get!(Session, session.id)
      assert updated.distilled_status == :completed
      assert updated.distilled_summary =~ "timezone"
      assert updated.distilled_model_used == "stub-model"
      assert updated.distilled_at != nil

      distillation =
        SessionDistillation
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.read_one!()

      assert distillation.status == :completed
      assert distillation.summary_json["session_summary"] =~ "timezone"
    end
  end

  describe "session without commit links" do
    test "sets distilled_status to skipped", %{session: session} do
      assert :ok =
               DistillCompletedSession.perform(%Oban.Job{
                 args: %{"session_id" => to_string(session.session_id)}
               })

      updated = Ash.get!(Session, session.id)
      assert updated.distilled_status == :skipped

      distillation =
        SessionDistillation
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.read_one!()

      assert distillation.status == :skipped
      assert distillation.error_reason == "no_commit_links"
    end
  end

  describe "re-trigger on commit link creation" do
    test "enqueues distillation job when commit link is created after skip", %{
      session: session
    } do
      # First, run distillation which will skip due to no commit links
      assert :ok =
               DistillCompletedSession.perform(%Oban.Job{
                 args: %{"session_id" => to_string(session.session_id)}
               })

      updated = Ash.get!(Session, session.id)
      assert updated.distilled_status == :skipped

      # Now create a commit link — this should enqueue a new distillation job
      commit =
        Ash.create!(Commit, %{
          commit_hash: "retrigger123",
          git_branch: "main",
          subject: "feat: retrigger test"
        })

      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      import Ecto.Query

      jobs =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "Spotter.Transcripts.Jobs.DistillCompletedSession",
            where: j.state == "available",
            where:
              fragment("json_extract(?, '$.session_id')", j.args) ==
                ^to_string(session.session_id)
          )
        )

      assert length(jobs) == 1
    end

    test "does not enqueue when session is not ended", %{project: project} do
      # Session without hook_ended_at
      session_not_ended =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/test2",
          cwd: "/home/user/distill-project",
          project_id: project.id,
          hook_ended_at: nil
        })

      commit =
        Ash.create!(Commit, %{
          commit_hash: "noend123",
          git_branch: "main",
          subject: "feat: not ended"
        })

      Ash.create!(SessionCommitLink, %{
        session_id: session_not_ended.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      import Ecto.Query

      jobs =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "Spotter.Transcripts.Jobs.DistillCompletedSession",
            where: j.state == "available",
            where:
              fragment("json_extract(?, '$.session_id')", j.args) ==
                ^to_string(session_not_ended.session_id)
          )
        )

      assert jobs == []
    end

    test "does not enqueue when session was not skipped with no_commit_links", %{
      session: session
    } do
      # Create a commit link FIRST, then distill (will complete, not skip)
      commit =
        Ash.create!(Commit, %{
          commit_hash: "completed123",
          git_branch: "main",
          subject: "feat: already completed"
        })

      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      assert :ok =
               DistillCompletedSession.perform(%Oban.Job{
                 args: %{"session_id" => to_string(session.session_id)}
               })

      updated = Ash.get!(Session, session.id)
      assert updated.distilled_status == :completed

      # Creating another commit link should NOT enqueue a new job
      commit2 =
        Ash.create!(Commit, %{
          commit_hash: "another456",
          git_branch: "main",
          subject: "feat: another commit"
        })

      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit2.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      import Ecto.Query

      jobs =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "Spotter.Transcripts.Jobs.DistillCompletedSession",
            where: j.state == "available"
          )
        )

      assert jobs == []
    end
  end

  describe "unique states allow re-enqueue after completion" do
    test "can insert a new job after previous one completed", %{session: session} do
      import Ecto.Query

      # Insert job1
      {:ok, job1} =
        %{session_id: to_string(session.session_id)}
        |> DistillCompletedSession.new()
        |> Oban.insert()

      # Force job1 to completed state
      Repo.update_all(
        from(j in Oban.Job, where: j.id == ^job1.id),
        set: [state: "completed", completed_at: DateTime.utc_now()]
      )

      # Insert job2 with same args
      {:ok, job2} =
        %{session_id: to_string(session.session_id)}
        |> DistillCompletedSession.new()
        |> Oban.insert()

      assert job2.id != job1.id
    end
  end
end
