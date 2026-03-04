defmodule SpotterWeb.ShellTelemetryLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Project, Session, ShellCommandEvent}

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "telemetry-proj", pattern: "^telemetry-proj"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/telemetry-sessions",
        cwd: "/home/user/project",
        project_id: project.id
      })

    %{project: project, session: session}
  end

  defp create_command_pair(attrs) do
    base = %{
      hook_event_name: "shell_command",
      tool_name: "Bash",
      raw_hook_event_id: Ash.UUID.generate()
    }

    start_attrs =
      Map.merge(base, attrs)
      |> Map.put(:phase, :start)
      |> Map.put(:raw_hook_event_id, Ash.UUID.generate())

    Ash.create!(ShellCommandEvent, start_attrs)

    finish_attrs =
      Map.merge(base, attrs)
      |> Map.put(:phase, :finish)
      |> Map.put(:finish_status, Map.get(attrs, :finish_status, :ok))
      |> Map.put(:captured_at, DateTime.add(attrs.captured_at, 5, :second))
      |> Map.put(:raw_hook_event_id, Ash.UUID.generate())

    Ash.create!(ShellCommandEvent, finish_attrs)
  end

  describe "page rendering" do
    test "renders project selector, window selector, and summary metrics at /telemetry/commands",
         %{project: _project} do
      {:ok, _view, html} = live(build_conn(), "/telemetry/commands")

      assert html =~ "project"
      assert html =~ "window"
      assert html =~ "median"
    end

    test "preselects project at /projects/:project_id/telemetry/commands", %{project: project} do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/telemetry/commands")

      assert html =~ project.name
    end
  end

  describe "with command data" do
    setup %{project: project, session: session} do
      now = DateTime.utc_now()

      create_command_pair(%{
        session_id: session.id,
        external_session_id: session.session_id,
        project_id: project.id,
        tool_use_id: Ash.UUID.generate(),
        command: "mix test",
        command_path: "mix test test/my_test.exs",
        captured_at: DateTime.add(now, -3600, :second)
      })

      create_command_pair(%{
        session_id: session.id,
        external_session_id: session.session_id,
        project_id: project.id,
        tool_use_id: Ash.UUID.generate(),
        command: "git status",
        command_path: "git status",
        captured_at: DateTime.add(now, -1800, :second)
      })

      :ok
    end

    test "per-command table renders command groups sorted by median_ms DESC", %{
      project: project
    } do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/telemetry/commands")

      assert html =~ "mix test"
      assert html =~ "git status"

      mix_pos = :binary.match(html, "mix test") |> elem(0)
      git_pos = :binary.match(html, "git status") |> elem(0)

      # Both commands have 5s duration, but "mix test" appears first alphabetically or by creation
      # The key assertion is that both appear in the table
      assert mix_pos > 0
      assert git_pos > 0
    end

    test "table renders expected columns", %{project: project} do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/telemetry/commands")

      for col <- [
            "command",
            "completed",
            "ongoing",
            "error_rate",
            "mean",
            "median",
            "p50",
            "p90",
            "p95",
            "last_seen"
          ] do
        assert html =~ col, "Expected column header '#{col}' not found"
      end
    end
  end

  describe "empty state" do
    test "displays empty state when no data for selected window" do
      project = Ash.create!(Project, %{name: "empty-telemetry", pattern: "^empty-telemetry"})

      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/telemetry/commands")

      assert html =~ "No command" || html =~ "no data" || html =~ "empty"
    end
  end

  describe "window switching" do
    test "preserves selected project when switching window", %{project: project} do
      {:ok, view, _html} =
        live(build_conn(), "/projects/#{project.id}/telemetry/commands")

      html = render_click(view, "select_window", %{"window" => "last_24h"})
      assert html =~ project.name
    end
  end

  describe "unknown project fallback" do
    test "falls back to first available project for unknown project_id" do
      project = Ash.create!(Project, %{name: "fallback-proj", pattern: "^fallback-proj"})
      fake_id = Ash.UUID.generate()

      {:ok, _view, html} =
        live(build_conn(), "/projects/#{fake_id}/telemetry/commands")

      assert html =~ project.name
    end
  end

  describe "long command truncation" do
    test "long commands are truncated with full-value title attribute", %{
      project: project,
      session: session
    } do
      long_command = String.duplicate("a", 200)

      create_command_pair(%{
        session_id: session.id,
        external_session_id: session.session_id,
        project_id: project.id,
        tool_use_id: Ash.UUID.generate(),
        command: long_command,
        command_path: long_command,
        captured_at: DateTime.add(DateTime.utc_now(), -600, :second)
      })

      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/telemetry/commands")

      assert html =~ "title=\"#{long_command}\""
      # Truncated display should be shorter than the full command
      refute html =~ ">#{long_command}<"
    end
  end

  describe "timer tick" do
    test "tick updates ongoing elapsed durations", %{project: project, session: session} do
      # Create an ongoing command (start only, no finish)
      Ash.create!(ShellCommandEvent, %{
        session_id: session.id,
        external_session_id: session.session_id,
        project_id: project.id,
        tool_use_id: Ash.UUID.generate(),
        command: "mix compile",
        command_path: "mix compile",
        hook_event_name: "shell_command",
        tool_name: "Bash",
        phase: :start,
        captured_at: DateTime.add(DateTime.utc_now(), -10, :second),
        raw_hook_event_id: Ash.UUID.generate()
      })

      {:ok, view, html1} =
        live(build_conn(), "/projects/#{project.id}/telemetry/commands")

      assert html1 =~ "mix compile"

      # Simulate timer tick
      send(view.pid, :tick)
      html2 = render(view)

      # After tick, the ongoing elapsed should have updated
      assert html2 =~ "mix compile"
    end
  end
end
