defmodule Mix.Tasks.Spotter.Transcripts.CompareTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "option parsing" do
    test "parses --left-session and --right-session (repeated)" do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            "session-a",
            "--left-session",
            "session-b",
            "--right-session",
            "session-c"
          ])
        end)

      assert is_binary(output)
    end

    test "parses --tool filter" do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            "session-a",
            "--right-session",
            "session-b",
            "--tool",
            "Bash"
          ])
        end)

      assert is_binary(output)
    end

    test "parses --command-contains filter" do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            "session-a",
            "--right-session",
            "session-b",
            "--command-contains",
            "mix test"
          ])
        end)

      assert is_binary(output)
    end

    test "parses --group-by option" do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            "session-a",
            "--right-session",
            "session-b",
            "--group-by",
            "command_fingerprint"
          ])
        end)

      assert is_binary(output)
    end
  end

  describe "output formats" do
    test "supports --format table" do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            "session-a",
            "--right-session",
            "session-b",
            "--format",
            "table"
          ])
        end)

      assert is_binary(output)
    end

    test "supports --format json" do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            "session-a",
            "--right-session",
            "session-b",
            "--format",
            "json"
          ])
        end)

      assert is_binary(output)
    end
  end

  describe "error handling" do
    test "returns error with empty left cohort" do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--right-session",
            "session-a"
          ])
        end)

      assert output =~ ~r/error|Error|left.*required|no.*left/i
    end

    test "returns error with empty right cohort" do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            "session-a"
          ])
        end)

      assert output =~ ~r/error|Error|right.*required|no.*right/i
    end
  end
end
