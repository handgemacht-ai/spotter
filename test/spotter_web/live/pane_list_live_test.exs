defmodule SpotterWeb.PaneListLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Project, Session}

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "test-dashboard", pattern: "^test-dashboard"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test-sessions",
        cwd: "/home/user/project",
        project_id: project.id
      })

    session_with_lines =
      Ash.update!(session, %{added_delta: 42, removed_delta: 7}, action: :add_line_stats)

    %{project: project, session: session_with_lines}
  end

  describe "dashboard renders without session table" do
    test "contains dashboard root testid" do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-testid="dashboard-root")
    end

    test "does not contain Session Transcripts heading" do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ "Session Transcripts"
    end

    test "does not contain session rows", %{session: _session} do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ ~s(data-testid="session-row")
    end

    test "does not contain import button" do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ ~s(data-testid="import-button")
    end

    test "renders Dashboard heading" do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "Dashboard"
    end
  end
end
