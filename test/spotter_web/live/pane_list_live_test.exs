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

    test "does not contain ingest button or sync text", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ "Ingest"
      refute html =~ ~s(data-testid="sync-transcripts-button")
      refute html =~ "No projects synced yet"
    end

    test "renders line stats for session with lines", %{session: _session} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "+42"
      assert html =~ "-7"
    end
  end

  describe "project picker filtering" do
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

    test "filters to a single project", %{proj_a: _proj_a, proj_b: proj_b} do
      {:ok, view, _html} = live(build_conn(), "/")

      html = render_click(view, "filter_project", %{"project-id" => proj_b.id})

      assert html =~ ~s(class="project-name">proj-beta</span>)
      refute html =~ ~s(class="project-name">proj-alpha</span>)

      # Also verify proj_a's filter chip is still rendered (not hidden from filter bar)
      assert html =~ "proj-alpha"
    end

    test "resets to all projects", %{proj_a: _proj_a, proj_b: proj_b} do
      {:ok, view, _html} = live(build_conn(), "/")

      render_click(view, "filter_project", %{"project-id" => proj_b.id})
      html = render_click(view, "filter_project", %{"project-id" => "all"})

      assert html =~ ~s(class="project-name">proj-alpha</span>)
      assert html =~ ~s(class="project-name">proj-beta</span>)
    end
  end

  describe "study queue" do
    test "always renders study queue with empty state when no items due", %{} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-testid="study-queue")
      assert html =~ "No items due today."
    end
  end
end
