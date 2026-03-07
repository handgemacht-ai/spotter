defmodule Spotter.Transcripts.Jobs.SyncTranscriptsTranscriptPathTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.Jobs.SyncTranscripts
  alias Spotter.Transcripts.Session

  require Ash.Query

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    tmp_dir =
      Path.join(System.tmp_dir!(), "spotter_tp_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  describe "sync_session_by_id/2 with transcript_path option" do
    test "uses transcript_path when file exists, skipping root search", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()

      # Write the JSONL file at a custom path (not under any configured root)
      custom_dir = Path.join(tmp_dir, "custom-location")
      file_path = write_session_jsonl(custom_dir, session_id)

      result =
        SyncTranscripts.sync_session_by_id(session_id, transcript_path: file_path)

      assert result.status == :ok
      assert result.session_id == session_id
      assert result.ingested_messages > 0

      session = Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one!()
      assert session.session_id == session_id
    end

    test "falls back to root search when transcript_path file is missing", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()

      # Write file under a configured root (simulate it being discoverable)
      root_dir = Path.join(tmp_dir, "root-projects")
      project_dir = Path.join(root_dir, "test-project")
      write_session_jsonl(project_dir, session_id)

      # Point transcript_path to a non-existent file
      missing_path = Path.join(tmp_dir, "gone/#{session_id}.jsonl")

      result =
        SyncTranscripts.sync_session_by_id(session_id,
          transcript_path: missing_path,
          transcript_roots: [root_dir]
        )

      assert result.status == :ok
      assert result.session_id == session_id
      assert result.ingested_messages > 0
    end

    test "empty transcript_path is ignored, behaves as normal search", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()

      root_dir = Path.join(tmp_dir, "root-projects")
      project_dir = Path.join(root_dir, "test-project")
      write_session_jsonl(project_dir, session_id)

      result =
        SyncTranscripts.sync_session_by_id(session_id,
          transcript_path: "",
          transcript_roots: [root_dir]
        )

      assert result.status == :ok
      assert result.session_id == session_id
    end

    test "nil transcript_path is ignored, behaves as normal search", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()

      root_dir = Path.join(tmp_dir, "root-projects")
      project_dir = Path.join(root_dir, "test-project")
      write_session_jsonl(project_dir, session_id)

      result =
        SyncTranscripts.sync_session_by_id(session_id,
          transcript_path: nil,
          transcript_roots: [root_dir]
        )

      assert result.status == :ok
      assert result.session_id == session_id
    end
  end

  describe "find_transcript_file multi-root search" do
    test "searches all configured transcript_roots in order", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()

      # Create two roots, file only exists in the second one
      root1 = Path.join(tmp_dir, "root-first")
      root2 = Path.join(tmp_dir, "root-second")
      File.mkdir_p!(root1)

      project_dir = Path.join(root2, "test-project")
      write_session_jsonl(project_dir, session_id)

      result =
        SyncTranscripts.sync_session_by_id(session_id,
          transcript_roots: [root1, root2]
        )

      assert result.status == :ok
      assert result.session_id == session_id
      assert result.ingested_messages > 0
    end
  end

  describe "session_end idempotency" do
    test "duplicate sync_session_by_id calls do not duplicate messages", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()
      custom_dir = Path.join(tmp_dir, "idempotent-test")
      file_path = write_session_jsonl(custom_dir, session_id)

      result1 =
        SyncTranscripts.sync_session_by_id(session_id, transcript_path: file_path)

      result2 =
        SyncTranscripts.sync_session_by_id(session_id, transcript_path: file_path)

      assert result1.status == :ok
      assert result2.status == :ok

      # Message count should be identical (upsert, not insert)
      assert result1.ingested_messages == result2.ingested_messages

      session = Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one!()

      db_messages =
        Spotter.Transcripts.Message
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.read!()

      assert length(db_messages) == result1.ingested_messages
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
end
