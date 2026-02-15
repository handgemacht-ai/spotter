defmodule Spotter.Services.TranscriptTailWorkerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Services.TranscriptTailSupervisor
  alias Spotter.Services.TranscriptTailWorker

  setup do
    Sandbox.checkout(Spotter.Repo)
    Sandbox.mode(Spotter.Repo, {:shared, self()})

    Ash.create!(Spotter.Transcripts.Project, %{name: "test-tail", pattern: "^test"})

    tmp_dir = Path.join(System.tmp_dir!(), "tail_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  defp write_jsonl(dir, session_id) do
    path = Path.join(dir, "#{session_id}.jsonl")

    lines = [
      %{
        "uuid" => "#{session_id}-sys",
        "type" => "system",
        "sessionId" => session_id,
        "cwd" => "test-tail/project",
        "version" => "1.0.0",
        "timestamp" => "2026-02-01T12:00:00Z"
      },
      %{
        "uuid" => "#{session_id}-usr",
        "type" => "human",
        "role" => "user",
        "content" => [%{"type" => "text", "text" => "hello"}],
        "timestamp" => "2026-02-01T12:00:01Z"
      }
    ]

    File.write!(path, Enum.map_join(lines, "\n", &Jason.encode!/1) <> "\n")
    path
  end

  describe "ensure_worker/2" do
    test "starts a worker for a session", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()
      path = write_jsonl(tmp_dir, session_id)

      assert :ok = TranscriptTailSupervisor.ensure_worker(session_id, path)

      # Worker should be registered
      assert [{pid, _}] =
               Registry.lookup(Spotter.Services.TranscriptTailRegistry, session_id)

      assert Process.alive?(pid)

      # Cleanup
      TranscriptTailSupervisor.stop_worker(session_id)
    end

    test "is idempotent for duplicate calls", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()
      path = write_jsonl(tmp_dir, session_id)

      assert :ok = TranscriptTailSupervisor.ensure_worker(session_id, path)
      assert :ok = TranscriptTailSupervisor.ensure_worker(session_id, path)

      # Only one worker
      assert [{_pid, _}] =
               Registry.lookup(Spotter.Services.TranscriptTailRegistry, session_id)

      TranscriptTailSupervisor.stop_worker(session_id)
    end
  end

  describe "stop_worker/1" do
    test "stops a running worker", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()
      path = write_jsonl(tmp_dir, session_id)

      TranscriptTailSupervisor.ensure_worker(session_id, path)
      [{pid, _}] = Registry.lookup(Spotter.Services.TranscriptTailRegistry, session_id)

      assert :ok = TranscriptTailSupervisor.stop_worker(session_id)
      Process.sleep(50)

      refute Process.alive?(pid)
    end

    test "is a no-op for unknown sessions" do
      assert :ok = TranscriptTailSupervisor.stop_worker("nonexistent")
    end
  end

  describe "worker publishes on file change" do
    test "broadcasts transcript_updated after debounce", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()
      path = write_jsonl(tmp_dir, session_id)

      Phoenix.PubSub.subscribe(Spotter.PubSub, "session_transcripts:#{session_id}")

      TranscriptTailSupervisor.ensure_worker(session_id, path)

      # Append a new line to the file
      Process.sleep(200)

      new_line =
        Jason.encode!(%{
          "uuid" => "#{session_id}-usr2",
          "type" => "human",
          "role" => "user",
          "content" => [%{"type" => "text", "text" => "world"}],
          "timestamp" => "2026-02-01T12:00:02Z"
        })

      File.write!(path, new_line <> "\n", [:append])

      # Wait for debounce (500ms) + processing
      assert_receive {:transcript_updated, ^session_id, _count}, 3000

      TranscriptTailSupervisor.stop_worker(session_id)
    end
  end

  describe "worker init" do
    test "starts successfully for nonexistent file (tail -F waits for creation)" do
      session_id = Ash.UUID.generate()

      result =
        TranscriptTailSupervisor.ensure_worker(session_id, "/nonexistent/transcript.jsonl")

      assert :ok = result

      # Clean up
      TranscriptTailSupervisor.stop_worker(session_id)
    end
  end

  describe "via/1" do
    test "returns a via tuple" do
      assert {:via, Registry, {Spotter.Services.TranscriptTailRegistry, "test"}} =
               TranscriptTailWorker.via("test")
    end
  end
end
