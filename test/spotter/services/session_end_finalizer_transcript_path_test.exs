defmodule Spotter.Services.SessionEndFinalizerTranscriptPathTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Services.SessionEndFinalizer
  alias Spotter.Transcripts.{Message, Project, Session}

  require Ash.Query

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)

    tmp_dir =
      Path.join(System.tmp_dir!(), "spotter_fin_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    project = Ash.create!(Project, %{name: "finalizer-tp-test", pattern: "^finalizer-tp-test"})

    on_exit(fn ->
      Sandbox.stop_owner(pid)
      File.rm_rf!(tmp_dir)
    end)

    %{project: project, tmp_dir: tmp_dir}
  end

  describe "finalize/3 with transcript_path" do
    test "forwards transcript_path to sync and ingests session", %{
      project: project,
      tmp_dir: tmp_dir
    } do
      session_id = Ash.UUID.generate()

      session =
        Ash.create!(Session, %{
          session_id: session_id,
          transcript_dir: "finalizer-tp-test",
          cwd: "/home/user/finalizer-project",
          project_id: project.id,
          started_at: DateTime.utc_now()
        })

      # Write JSONL file at a custom path (not discoverable by root search)
      custom_dir = Path.join(tmp_dir, "custom-finalizer-path")
      file_path = write_session_jsonl(custom_dir, session_id)

      result =
        SessionEndFinalizer.finalize(session.session_id, %{"cwd" => session.cwd},
          transcript_path: file_path
        )

      assert result.sync_status == :ok
      assert result.ingested_messages > 0

      db_messages =
        Message
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.read!()

      assert db_messages != []
    end

    test "session_end without cwd or transcript_path still returns ok", %{project: project} do
      session_id = Ash.UUID.generate()

      Ash.create!(Session, %{
        session_id: session_id,
        transcript_dir: "finalizer-tp-test",
        cwd: "/home/user/finalizer-project",
        project_id: project.id,
        started_at: DateTime.utc_now()
      })

      # No cwd, no transcript_path — should not crash
      result = SessionEndFinalizer.finalize(session_id, %{})

      assert result.marked_ended == :ok
    end
  end

  defp write_session_jsonl(dir, session_id) do
    File.mkdir_p!(dir)

    lines = [
      %{
        "uuid" => "#{session_id}-system",
        "type" => "system",
        "sessionId" => session_id,
        "cwd" => "finalizer-tp-test/project",
        "version" => "1.0.0",
        "timestamp" => "2026-02-01T12:00:00Z"
      },
      %{
        "uuid" => "#{session_id}-user-1",
        "type" => "human",
        "role" => "user",
        "content" => [%{"type" => "text", "text" => "hello"}],
        "timestamp" => "2026-02-01T12:00:01Z"
      }
    ]

    path = Path.join(dir, "#{session_id}.jsonl")
    content = Enum.map_join(lines, "\n", &Jason.encode!/1)
    File.write!(path, content)
    path
  end
end
