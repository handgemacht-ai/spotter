defmodule Mix.Tasks.Spotter.Transcripts.InspectTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Project, Session}

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "inspect-test", pattern: "^inspect"})
    session_id = Ash.UUID.generate()

    Ash.create!(Session, %{
      session_id: session_id,
      transcript_dir: "test-dir",
      cwd: "/tmp/test",
      project_id: project.id
    })

    %{session_id: session_id}
  end

  describe "option parsing" do
    test "requires --session option" do
      Mix.Task.reenable("spotter.transcripts.inspect")

      assert catch_exit(
               capture_io(fn ->
                 Mix.Task.run("spotter.transcripts.inspect", [])
               end)
             ) == {:shutdown, 1}
    end

    test "accepts --session option", %{session_id: sid} do
      Mix.Task.reenable("spotter.transcripts.inspect")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.inspect", ["--session", sid])
        end)

      assert is_binary(output)
    end

    test "accepts --tool-use-id option", %{session_id: sid} do
      Mix.Task.reenable("spotter.transcripts.inspect")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.inspect", [
            "--session",
            sid,
            "--tool-use-id",
            "toolu_xyz"
          ])
        end)

      assert is_binary(output)
    end

    test "accepts --context option for surrounding lines", %{session_id: sid} do
      Mix.Task.reenable("spotter.transcripts.inspect")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.inspect", ["--session", sid, "--context", "5"])
        end)

      assert is_binary(output)
    end
  end

  describe "output formats" do
    test "supports --format table (default)", %{session_id: sid} do
      Mix.Task.reenable("spotter.transcripts.inspect")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.inspect", ["--session", sid, "--format", "table"])
        end)

      assert is_binary(output)
    end

    test "supports --format json", %{session_id: sid} do
      Mix.Task.reenable("spotter.transcripts.inspect")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.inspect", ["--session", sid, "--format", "json"])
        end)

      assert is_binary(output)
    end
  end
end
