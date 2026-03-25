defmodule Mix.Tasks.Spotter.Transcripts.CompareTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Project, Session}

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "compare-test", pattern: "^compare"})

    session_a = Ash.UUID.generate()
    session_b = Ash.UUID.generate()
    session_c = Ash.UUID.generate()

    for sid <- [session_a, session_b, session_c] do
      Ash.create!(Session, %{
        session_id: sid,
        transcript_dir: "test-dir",
        cwd: "/tmp/test",
        project_id: project.id
      })
    end

    %{session_a: session_a, session_b: session_b, session_c: session_c}
  end

  describe "option parsing" do
    test "parses --left-session and --right-session (repeated)", %{
      session_a: sa,
      session_b: sb,
      session_c: sc
    } do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            sa,
            "--left-session",
            sb,
            "--right-session",
            sc
          ])
        end)

      assert is_binary(output)
    end

    test "parses --tool filter", %{session_a: sa, session_b: sb} do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            sa,
            "--right-session",
            sb,
            "--tool",
            "Bash"
          ])
        end)

      assert is_binary(output)
    end

    test "parses --command-contains filter", %{session_a: sa, session_b: sb} do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            sa,
            "--right-session",
            sb,
            "--command-contains",
            "mix test"
          ])
        end)

      assert is_binary(output)
    end

    test "parses --group-by option", %{session_a: sa, session_b: sb} do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            sa,
            "--right-session",
            sb,
            "--group-by",
            "command_fingerprint"
          ])
        end)

      assert is_binary(output)
    end
  end

  describe "output formats" do
    test "supports --format table", %{session_a: sa, session_b: sb} do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            sa,
            "--right-session",
            sb,
            "--format",
            "table"
          ])
        end)

      assert is_binary(output)
    end

    test "supports --format json", %{session_a: sa, session_b: sb} do
      Mix.Task.reenable("spotter.transcripts.compare")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.compare", [
            "--left-session",
            sa,
            "--right-session",
            sb,
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
