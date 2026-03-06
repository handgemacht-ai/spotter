defmodule SpotterWeb.SessionsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Project, Session}

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "test-sessions", pattern: "^test-sessions"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test-sessions",
        cwd: "/home/user/project",
        project_id: project.id
      })

    %{project: project, session: session}
  end

  describe "SessionsLive mounts at /sessions" do
    test "mounts successfully and renders sessions root", %{} do
      {:ok, _view, html} = live(build_conn(), "/sessions")

      assert html =~ ~s(data-testid="sessions-root")
    end

    test "renders session table with session rows", %{session: _session} do
      {:ok, _view, html} = live(build_conn(), "/sessions")

      assert html =~ ~s(data-testid="session-row")
    end

    test "renders Session Transcripts heading", %{} do
      {:ok, _view, html} = live(build_conn(), "/sessions")

      assert html =~ "Session Transcripts"
    end
  end
end
