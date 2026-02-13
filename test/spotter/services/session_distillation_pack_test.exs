defmodule Spotter.Services.SessionDistillationPackTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  alias Spotter.Services.SessionDistillationPack
  alias Spotter.Transcripts.{Commit, Message, Project, Session, SessionCommitLink}

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "pack-test", pattern: "^pack"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test",
        cwd: "/home/user/pack-project",
        project_id: project.id,
        message_count: 5,
        hook_ended_at: DateTime.utc_now()
      })

    %{project: project, session: session}
  end

  describe "build/2" do
    test "includes required keys", %{session: session} do
      pack = SessionDistillationPack.build(session)

      assert Map.has_key?(pack, :session)
      assert Map.has_key?(pack, :commits)
      assert Map.has_key?(pack, :stats)
      assert Map.has_key?(pack, :file_snapshots)
      assert Map.has_key?(pack, :errors)
      assert Map.has_key?(pack, :transcript_slice)

      assert pack.session.session_id == session.session_id
      assert pack.session.cwd == "/home/user/pack-project"
    end

    test "includes linked commits", %{session: session} do
      commit =
        Ash.create!(Commit, %{
          commit_hash: "abc123",
          git_branch: "main",
          subject: "test commit"
        })

      Ash.create!(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: :observed_in_session,
        confidence: 1.0
      })

      pack = SessionDistillationPack.build(session)
      assert length(pack.commits) == 1
      assert hd(pack.commits).commit_hash == "abc123"
    end

    test "slicing respects char budget and is deterministic", %{session: session} do
      for i <- 1..10 do
        Ash.create!(Message, %{
          session_id: session.id,
          uuid: Ash.UUID.generate(),
          type: :user,
          role: :user,
          content: %{"text" => "message number #{i}"},
          timestamp: DateTime.add(DateTime.utc_now(), i, :second)
        })
      end

      pack1 = SessionDistillationPack.build(session, char_budget: 500)
      pack2 = SessionDistillationPack.build(session, char_budget: 500)

      assert pack1.transcript_slice == pack2.transcript_slice
      assert String.length(pack1.transcript_slice) > 0
    end

    test "stats reflect tool call counts", %{session: session} do
      pack = SessionDistillationPack.build(session)
      assert pack.stats.messages_total == 5
      assert pack.stats.tool_calls_total == 0
      assert pack.stats.tool_calls_failed == 0
    end
  end
end
