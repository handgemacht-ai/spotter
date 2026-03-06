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

  describe "project filter chips on /sessions" do
    setup do
      proj_a = Ash.create!(Project, %{name: "proj-alpha", pattern: "^proj-alpha"})
      proj_b = Ash.create!(Project, %{name: "proj-beta", pattern: "^proj-beta"})

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test-alpha",
        cwd: "/home/user/alpha",
        project_id: proj_a.id
      })

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/test-beta",
        cwd: "/home/user/beta",
        project_id: proj_b.id
      })

      %{proj_a: proj_a, proj_b: proj_b}
    end

    test "filters sessions when project chip is clicked", %{proj_b: proj_b} do
      {:ok, view, _html} = live(build_conn(), "/sessions")

      html = render_click(view, "filter_project", %{"project-id" => proj_b.id})

      assert html =~ ~s(class="project-name">proj-beta</span>)
      refute html =~ ~s(class="project-name">proj-alpha</span>)
    end
  end

  describe "/sessions/:session_id still resolves" do
    test "session detail page mounts for existing session", %{session: session} do
      {:ok, _view, html} = live(build_conn(), "/sessions/#{session.session_id}")

      assert html =~ ~s(data-testid="session-root")
    end
  end

  describe "sidebar contains Sessions link" do
    test "sidebar renders Sessions nav link on /sessions page" do
      {:ok, _view, html} = live(build_conn(), "/sessions")

      assert html =~ ~s(href="/sessions")
      assert html =~ ~s(data-nav-path="/sessions")
      assert html =~ "Sessions"
    end
  end
end
