defmodule Spotter.Transcripts.Jobs.SyncTranscriptsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.Jobs.SyncTranscripts
  alias Spotter.Transcripts.{JsonlParser, Message, Project, Session, SessionRework, Subagent}

  require Ash.Query

  @pubsub Spotter.PubSub

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    Phoenix.PubSub.subscribe(@pubsub, "sync:progress")

    project = Ash.create!(Project, %{name: "test-sync", pattern: "^test"})
    session_id = Ash.UUID.generate()

    session =
      Ash.create!(Session, %{
        session_id: session_id,
        transcript_dir: "test-dir",
        cwd: "/home/user/project",
        project_id: project.id
      })

    tmp_dir = Path.join(System.tmp_dir!(), "spotter_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{session: session, tmp_dir: tmp_dir}
  end

  describe "rework persistence via extract + upsert" do
    test "persists rework records for repeated file modifications", %{session: session} do
      messages = build_rework_messages()

      rework_records =
        JsonlParser.extract_session_rework_records(messages,
          session_cwd: "/home/user/project"
        )

      assert length(rework_records) == 2

      Enum.each(rework_records, fn record ->
        Ash.create!(SessionRework, Map.put(record, :session_id, session.id), action: :upsert)
      end)

      persisted =
        SessionRework
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.Query.sort(occurrence_index: :asc)
        |> Ash.read!()

      assert length(persisted) == 2
      assert Enum.at(persisted, 0).occurrence_index == 2
      assert Enum.at(persisted, 1).occurrence_index == 3
      assert Enum.at(persisted, 0).relative_path == "lib/foo.ex"
    end

    test "rerunning sync does not duplicate records (idempotent)", %{session: session} do
      messages = build_rework_messages()

      persist_rework!(session, messages)
      persist_rework!(session, messages)

      persisted =
        SessionRework
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.read!()

      assert length(persisted) == 2
    end

    test "failed tool results do not produce rework records", %{session: session} do
      messages = [
        assistant_write("tu-1", "/home/user/project/lib/foo.ex"),
        tool_result("tu-1", false),
        assistant_edit("tu-2", "/home/user/project/lib/foo.ex"),
        tool_result("tu-2", true),
        assistant_edit("tu-3", "/home/user/project/lib/foo.ex"),
        tool_result("tu-3", false)
      ]

      persist_rework!(session, messages)

      persisted =
        SessionRework
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.read!()

      # tu-1 is first success, tu-2 failed (ignored), tu-3 is second success -> 1 rework
      assert length(persisted) == 1
      assert hd(persisted).tool_use_id == "tu-3"
      assert hd(persisted).occurrence_index == 2
    end
  end

  defp write_session_jsonl(dir, session_id) do
    File.mkdir_p!(dir)

    lines = [
      %{
        "uuid" => "#{session_id}-system",
        "type" => "system",
        "sessionId" => session_id,
        "cwd" => "test-sync/project",
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

  describe "sync_session_file/2" do
    test "ingests messages from a JSONL file", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()
      dir = Path.join(tmp_dir, "test-project")
      file = write_session_jsonl(dir, session_id)

      result = SyncTranscripts.sync_session_file(file)

      assert result.status == :ok
      assert result.session_id == session_id
      assert result.ingested_messages > 0
    end

    test "is idempotent — repeated sync does not duplicate messages", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()
      dir = Path.join(tmp_dir, "test-project")
      file = write_session_jsonl(dir, session_id)

      SyncTranscripts.sync_session_file(file)
      result = SyncTranscripts.sync_session_file(file)

      assert result.status == :ok

      # Count messages in DB — should not be duplicated
      session = Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one!()

      db_messages =
        Message
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.read!()

      assert length(db_messages) == result.ingested_messages
    end

    test "backfills transcript_dir on existing session", %{session: session, tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "backfill-dir")
      file = write_session_jsonl(dir, session.session_id)

      SyncTranscripts.sync_session_file(file)

      updated = Session |> Ash.Query.filter(session_id == ^session.session_id) |> Ash.read_one!()
      assert updated.transcript_dir == "backfill-dir"
    end

    test "returns :not_found for file without session_id", %{tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "no-session")
      File.mkdir_p!(dir)
      path = Path.join(dir, "empty.jsonl")

      File.write!(
        path,
        Jason.encode!(%{"type" => "system", "timestamp" => "2026-02-01T12:00:00Z"})
      )

      result = SyncTranscripts.sync_session_file(path)
      assert result.status == :not_found
    end

    test "returns :error for nonexistent file" do
      result = SyncTranscripts.sync_session_file("/nonexistent/path.jsonl")
      assert result.status == :error
    end

    test "persists raw_payload on ingested messages", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()
      dir = Path.join(tmp_dir, "raw-payload")
      file = write_session_jsonl(dir, session_id)

      result = SyncTranscripts.sync_session_file(file)
      assert result.status == :ok

      session = Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one!()

      [first_message | _] =
        Message
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.Query.sort(timestamp: :asc)
        |> Ash.read!()

      assert is_map(first_message.raw_payload)
      assert first_message.raw_payload["uuid"] == "#{session_id}-system"
      assert first_message.raw_payload["sessionId"] == session_id
    end

    test "derives subagent_type from parent Task metadata and agent_progress", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()
      dir = Path.join(tmp_dir, "subagent-type")
      file = Path.join(dir, "#{session_id}.jsonl")
      File.mkdir_p!(dir)

      lines = [
        %{
          "uuid" => "#{session_id}-system",
          "type" => "system",
          "sessionId" => session_id,
          "cwd" => "test-sync/project",
          "version" => "1.0.0",
          "timestamp" => "2026-02-01T12:00:00Z"
        },
        %{
          "uuid" => "#{session_id}-assistant",
          "type" => "assistant",
          "sessionId" => session_id,
          "timestamp" => "2026-02-01T12:00:01Z",
          "message" => %{
            "role" => "assistant",
            "content" => [
              %{
                "type" => "tool_use",
                "id" => "task-tool-1",
                "name" => "Task",
                "input" => %{"subagent_type" => "research"}
              }
            ]
          }
        },
        %{
          "uuid" => "#{session_id}-progress",
          "type" => "progress",
          "sessionId" => session_id,
          "timestamp" => "2026-02-01T12:00:02Z",
          "data" => %{"type" => "agent_progress", "agentId" => "agent-xyz"},
          "parentToolUseID" => "task-tool-1"
        }
      ]

      File.write!(file, Enum.map_join(lines, "\n", &Jason.encode!/1))

      subagent_dir = Path.join([dir, session_id, "subagents"])
      File.mkdir_p!(subagent_dir)

      subagent_lines = [
        %{
          "uuid" => "#{session_id}-sub-system",
          "type" => "system",
          "sessionId" => session_id,
          "timestamp" => "2026-02-01T12:00:03Z"
        },
        %{
          "uuid" => "#{session_id}-sub-assistant",
          "type" => "assistant",
          "sessionId" => session_id,
          "timestamp" => "2026-02-01T12:00:04Z",
          "message" => %{"role" => "assistant", "content" => "hello from subagent"}
        }
      ]

      File.write!(
        Path.join(subagent_dir, "agent-agent-xyz.jsonl"),
        Enum.map_join(subagent_lines, "\n", &Jason.encode!/1)
      )

      result = SyncTranscripts.sync_session_file(file)
      assert result.status == :ok

      session = Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one!()
      agent_id = "agent-xyz"

      subagent =
        Subagent
        |> Ash.Query.filter(session_id == ^session.id and agent_id == ^agent_id)
        |> Ash.read_one!()

      assert subagent.subagent_type == "research"
    end
  end

  describe "sync_session_by_id/2" do
    test "returns :not_found when no transcript file exists" do
      result = SyncTranscripts.sync_session_by_id(Ash.UUID.generate())
      assert result.status == :not_found
      assert result.ingested_messages == 0
    end
  end

  describe "perform/1 with data" do
    test "emits sync_started, sync_progress, and sync_completed with run_id", %{tmp_dir: tmp_dir} do
      run_id = Ash.UUID.generate()
      project_dir = Path.join(tmp_dir, "my-project")
      write_session_jsonl(project_dir, Ash.UUID.generate())

      job = %Oban.Job{
        args: %{
          "project_name" => "test-proj",
          "pattern" => "^my-project",
          "transcripts_dir" => tmp_dir,
          "run_id" => run_id
        }
      }

      assert :ok = SyncTranscripts.perform(job)

      assert_received {:sync_started,
                       %{
                         run_id: ^run_id,
                         project: "test-proj",
                         dirs_total: 1,
                         sessions_total: 1
                       }}

      assert_received {:sync_progress,
                       %{
                         run_id: ^run_id,
                         project: "test-proj",
                         dirs_done: 1,
                         dirs_total: 1,
                         sessions_done: 1,
                         sessions_total: 1
                       }}

      assert_received {:sync_completed,
                       %{
                         run_id: ^run_id,
                         project: "test-proj",
                         dirs_synced: 1,
                         sessions_synced: 1,
                         duration_ms: _
                       }}
    end

    test "emits progress for multiple directories", %{tmp_dir: tmp_dir} do
      run_id = Ash.UUID.generate()
      write_session_jsonl(Path.join(tmp_dir, "multi-a"), Ash.UUID.generate())
      write_session_jsonl(Path.join(tmp_dir, "multi-b"), Ash.UUID.generate())

      job = %Oban.Job{
        args: %{
          "project_name" => "multi-proj",
          "pattern" => "^multi-",
          "transcripts_dir" => tmp_dir,
          "run_id" => run_id
        }
      }

      assert :ok = SyncTranscripts.perform(job)

      assert_received {:sync_started, %{run_id: ^run_id, dirs_total: 2, sessions_total: 2}}

      # Two progress messages, one per dir
      assert_received {:sync_progress, %{run_id: ^run_id, dirs_done: 1}}
      assert_received {:sync_progress, %{run_id: ^run_id, dirs_done: 2}}

      assert_received {:sync_completed, %{run_id: ^run_id, dirs_synced: 2, sessions_synced: 2}}
    end
  end

  describe "perform/1 with empty run" do
    test "emits sync_started and sync_completed with zero counts", %{tmp_dir: tmp_dir} do
      run_id = Ash.UUID.generate()
      # No matching directories

      job = %Oban.Job{
        args: %{
          "project_name" => "empty-proj",
          "pattern" => "^nonexistent",
          "transcripts_dir" => tmp_dir,
          "run_id" => run_id
        }
      }

      assert :ok = SyncTranscripts.perform(job)

      assert_received {:sync_started,
                       %{
                         run_id: ^run_id,
                         project: "empty-proj",
                         dirs_total: 0,
                         sessions_total: 0
                       }}

      assert_received {:sync_completed,
                       %{
                         run_id: ^run_id,
                         project: "empty-proj",
                         dirs_synced: 0,
                         sessions_synced: 0
                       }}
    end
  end

  describe "perform/1 without run_id" do
    test "still works with nil run_id for backward compat", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "compat-project")
      write_session_jsonl(project_dir, Ash.UUID.generate())

      job = %Oban.Job{
        args: %{
          "project_name" => "compat-proj",
          "pattern" => "^compat-project",
          "transcripts_dir" => tmp_dir
        }
      }

      assert :ok = SyncTranscripts.perform(job)

      assert_received {:sync_started, %{run_id: nil, project: "compat-proj"}}
      assert_received {:sync_completed, %{run_id: nil, project: "compat-proj"}}
    end
  end

  describe "sync_all/0 deprecation" do
    test "logs a deprecation warning when called" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          # credo:disable-for-next-line Credo.Check.Refactor.Apply
          apply(SyncTranscripts, :sync_all, [])
        end)

      assert log =~ "deprecated"
    end
  end

  defp persist_rework!(session, messages) do
    rework_records =
      JsonlParser.extract_session_rework_records(messages,
        session_cwd: session.cwd
      )

    Enum.each(rework_records, fn record ->
      Ash.create!(SessionRework, Map.put(record, :session_id, session.id), action: :upsert)
    end)
  end

  defp build_rework_messages do
    [
      assistant_write("tu-1", "/home/user/project/lib/foo.ex"),
      tool_result("tu-1", false),
      assistant_edit("tu-2", "/home/user/project/lib/foo.ex"),
      tool_result("tu-2", false),
      assistant_edit("tu-3", "/home/user/project/lib/foo.ex"),
      tool_result("tu-3", false)
    ]
  end

  defp assistant_write(tool_use_id, file_path) do
    %{
      uuid: "msg-#{tool_use_id}",
      type: :assistant,
      role: :assistant,
      timestamp: ~U[2026-02-12 10:00:00Z],
      content: %{
        "blocks" => [
          %{
            "type" => "tool_use",
            "id" => tool_use_id,
            "name" => "Write",
            "input" => %{"file_path" => file_path}
          }
        ]
      }
    }
  end

  defp assistant_edit(tool_use_id, file_path) do
    %{
      uuid: "msg-#{tool_use_id}",
      type: :assistant,
      role: :assistant,
      timestamp: ~U[2026-02-12 10:01:00Z],
      content: %{
        "blocks" => [
          %{
            "type" => "tool_use",
            "id" => tool_use_id,
            "name" => "Edit",
            "input" => %{"file_path" => file_path}
          }
        ]
      }
    }
  end

  defp tool_result(tool_use_id, is_error) do
    %{
      uuid: "result-#{tool_use_id}",
      type: :tool_result,
      role: :user,
      timestamp: ~U[2026-02-12 10:00:01Z],
      content: %{
        "blocks" => [
          %{
            "type" => "tool_result",
            "tool_use_id" => tool_use_id,
            "is_error" => is_error,
            "content" => if(is_error, do: "Error", else: "OK")
          }
        ]
      }
    }
  end
end
