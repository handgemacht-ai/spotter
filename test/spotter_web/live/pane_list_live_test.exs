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

    %{project: project, session: session}
  end

  describe "dashboard renders transcript-only" do
    test "contains dashboard root testid", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-testid="dashboard-root")
    end

    test "contains Session Transcripts heading", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "Session Transcripts"
    end

    test "does not contain Claude Code Sessions pane heading", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ "Claude Code Sessions"
    end

    test "does not contain Other Panes heading", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ "Other Panes"
    end

    test "renders session rows when sessions exist", %{session: _session} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-testid="session-row")
    end

    test "does not contain tmux empty state", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ "No tmux panes found"
    end
  end
end
