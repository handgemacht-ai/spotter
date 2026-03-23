defmodule Mix.Tasks.Spotter.Transcripts.Slice.RegisterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Project, Session, ToolCallRun}

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "slice-test", pattern: "^slice-test"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/slice-sess",
        cwd: "/home/user/slice-test",
        project_id: project.id,
        started_at: DateTime.utc_now()
      })

    run =
      Ash.create!(ToolCallRun, %{
        tool_use_id: "toolu_test_#{Ash.UUID.generate()}",
        tool_name: "Bash",
        command: "mix test",
        status: :completed,
        duration_ms: 5000,
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        session_id: session.id,
        project_id: project.id
      })

    %{project: project, session: session, run: run}
  end

  describe "option parsing" do
    test "requires --session flag" do
      Mix.Task.reenable("spotter.transcripts.slice.register")

      assert catch_exit(
               capture_io(:stderr, fn ->
                 Mix.Task.run("spotter.transcripts.slice.register", [])
               end)
             )
    end

    test "creates slice with --session and --tool-use-id", %{session: session, run: run} do
      Mix.Task.reenable("spotter.transcripts.slice.register")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.slice.register", [
            "--session",
            session.session_id,
            "--tool-use-id",
            run.tool_use_id
          ])
        end)

      assert output =~ "Slice created:"
      assert output =~ "Highlighted runs: 1"
      assert output =~ "/sessions/#{session.session_id}?slice="
    end

    test "creates slice with search filters", %{session: session} do
      Mix.Task.reenable("spotter.transcripts.slice.register")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.slice.register", [
            "--session",
            session.session_id,
            "--tool",
            "Bash"
          ])
        end)

      assert output =~ "Slice created:"
      assert output =~ "Highlighted runs: 1"
    end

    test "accepts --title option", %{session: session, run: run} do
      Mix.Task.reenable("spotter.transcripts.slice.register")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.slice.register", [
            "--session",
            session.session_id,
            "--tool-use-id",
            run.tool_use_id,
            "--title",
            "My Custom Slice"
          ])
        end)

      assert output =~ "Title: My Custom Slice"
    end
  end

  describe "output formats" do
    test "supports --format json", %{session: session, run: run} do
      Mix.Task.reenable("spotter.transcripts.slice.register")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.slice.register", [
            "--session",
            session.session_id,
            "--tool-use-id",
            run.tool_use_id,
            "--format",
            "json"
          ])
        end)

      decoded = Jason.decode!(output)
      assert is_binary(decoded["id"])
      assert decoded["session_id"] == session.session_id
      assert decoded["highlight_count"] == 1
      assert decoded["url"] =~ "/sessions/#{session.session_id}?slice="
    end

    test "supports --format text (default)", %{session: session, run: run} do
      Mix.Task.reenable("spotter.transcripts.slice.register")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.slice.register", [
            "--session",
            session.session_id,
            "--tool-use-id",
            run.tool_use_id,
            "--format",
            "text"
          ])
        end)

      assert output =~ "Slice created:"
      assert output =~ "URL:"
    end
  end

  describe "error handling" do
    test "rejects invalid session ID" do
      Mix.Task.reenable("spotter.transcripts.slice.register")

      assert catch_exit(
               capture_io(:stderr, fn ->
                 Mix.Task.run("spotter.transcripts.slice.register", [
                   "--session",
                   "nonexistent-session"
                 ])
               end)
             )
    end

    test "rejects tool-use-id not in session", %{session: session} do
      Mix.Task.reenable("spotter.transcripts.slice.register")

      assert catch_exit(
               capture_io(:stderr, fn ->
                 Mix.Task.run("spotter.transcripts.slice.register", [
                   "--session",
                   session.session_id,
                   "--tool-use-id",
                   "toolu_nonexistent"
                 ])
               end)
             )
    end

    test "rejects empty search results", %{session: session} do
      Mix.Task.reenable("spotter.transcripts.slice.register")

      assert catch_exit(
               capture_io(:stderr, fn ->
                 Mix.Task.run("spotter.transcripts.slice.register", [
                   "--session",
                   session.session_id,
                   "--tool",
                   "NonExistentTool"
                 ])
               end)
             )
    end
  end
end
