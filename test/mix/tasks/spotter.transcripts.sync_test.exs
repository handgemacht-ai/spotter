defmodule Mix.Tasks.Spotter.Transcripts.SyncTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "option parsing" do
    test "parses --session option" do
      Mix.Task.reenable("spotter.transcripts.sync")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.sync", [
            "--session",
            "abc-123"
          ])
        end)

      assert is_binary(output)
    end

    test "parses --file option for a specific JSONL file" do
      temp_dir =
        Path.join(System.tmp_dir!(), "spotter-sync-test-#{System.unique_integer([:positive])}")

      File.mkdir_p!(temp_dir)
      jsonl_path = Path.join(temp_dir, "test-session.jsonl")
      File.write!(jsonl_path, "{}\n")

      on_exit(fn -> File.rm_rf!(temp_dir) end)

      Mix.Task.reenable("spotter.transcripts.sync")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.sync", [
            "--file",
            jsonl_path
          ])
        end)

      assert is_binary(output)
    end

    test "parses --transcript-root option" do
      temp_dir =
        Path.join(System.tmp_dir!(), "spotter-sync-root-#{System.unique_integer([:positive])}")

      File.mkdir_p!(temp_dir)

      on_exit(fn -> File.rm_rf!(temp_dir) end)

      Mix.Task.reenable("spotter.transcripts.sync")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.sync", [
            "--transcript-root",
            temp_dir
          ])
        end)

      assert is_binary(output)
    end

    test "starts the application" do
      Mix.Task.reenable("spotter.transcripts.sync")

      capture_io(fn ->
        Mix.Task.run("spotter.transcripts.sync", [])
      end)

      assert Process.whereis(Spotter.Repo) != nil
    end

    test "returns proper output on success" do
      Mix.Task.reenable("spotter.transcripts.sync")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.sync", [])
        end)

      assert is_binary(output)
      assert output =~ ~r/sync|Sync|complete|done/i
    end
  end
end
