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

  describe "project selection via URL" do
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

    test "selects project via URL query param", %{proj_b: proj_b} do
      {:ok, _view, html} = live(build_conn(), "/sessions?project=#{proj_b.id}")

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

  describe "project context from on_mount" do
    test "uses current_project_id from on_mount, no project filter chips" do
      project = Ash.create!(Project, %{name: "ctx-proj", pattern: "^ctx-proj"})

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/ctx-proj",
        cwd: "/home/user/ctx-proj",
        project_id: project.id
      })

      {:ok, _view, html} = live(build_conn(), "/sessions?project_id=#{project.id}")

      # Content is filtered by on_mount current_project_id
      assert html =~ "ctx-proj"

      # No project filter chips — project selection is in the sidebar now
      refute html =~ "filter_project"
      refute html =~ "filter-btn"
    end

    test "shows only selected project sessions, not other projects" do
      proj_a = Ash.create!(Project, %{name: "proj-visible", pattern: "^proj-visible"})
      proj_b = Ash.create!(Project, %{name: "proj-other", pattern: "^proj-other"})

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/proj-visible",
        cwd: "/home/user/proj-visible",
        project_id: proj_a.id
      })

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/proj-other",
        cwd: "/home/user/proj-other",
        project_id: proj_b.id
      })

      {:ok, _view, html} = live(build_conn(), "/sessions?project=#{proj_a.id}")

      # Only the selected project's section is rendered
      assert html =~ ~s(class="project-name">proj-visible</span>)
      refute html =~ ~s(class="project-name">proj-other</span>)

      # Session rows are present for the selected project
      assert html =~ ~s(data-testid="session-row")
    end
  end

  describe "pagination resets on project change" do
    test "navigating to a different project reloads sessions from page 1" do
      proj_a = Ash.create!(Project, %{name: "page-alpha", pattern: "^page-alpha"})
      proj_b = Ash.create!(Project, %{name: "page-beta", pattern: "^page-beta"})

      # Create sessions for both projects
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/page-alpha",
        cwd: "/home/user/page-alpha",
        project_id: proj_a.id
      })

      session_b =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/page-beta",
          cwd: "/home/user/page-beta",
          project_id: proj_b.id
        })

      # Start on project A
      {:ok, view, html} = live(build_conn(), "/sessions?project=#{proj_a.id}")
      assert html =~ "page-alpha"

      # Navigate to project B via patch (simulates sidebar project change)
      html = render_patch(view, "/sessions?project=#{proj_b.id}")

      # Project B's sessions are shown, project A's are not
      assert html =~ "page-beta"
      refute html =~ ~s(class="project-name">page-alpha</span>)

      # Session rows are present for the new project
      assert html =~ session_b.session_id
    end
  end

  describe "sidebar contains Sessions link" do
    test "sidebar renders Sessions nav link on /sessions page" do
      {:ok, _view, html} = live(build_conn(), "/sessions")

      assert html =~ ~s(href="/sessions?project=)
      assert html =~ ~s(data-nav-path="/sessions")
      assert html =~ "Sessions"
    end
  end
end
