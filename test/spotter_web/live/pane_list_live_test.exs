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

    test "renders session row for session with data", %{session: _session} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-testid="session-row")
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

    test "resets to first project when all is clicked", %{proj_a: _proj_a, proj_b: proj_b} do
      {:ok, view, _html} = live(build_conn(), "/")

      render_click(view, "filter_project", %{"project-id" => proj_b.id})
      html = render_click(view, "filter_project", %{"project-id" => "all"})

      # "all" normalizes to the first project (auto-select), so only the first
      # project section is rendered; verify the filter bar still contains both chips.
      assert html =~ "proj-alpha"
      assert html =~ "proj-beta"
      assert html =~ ~s(class="project-name">test-dashboard</span>)
    end
  end

  describe "last updated display and sort" do
    setup do
      project = Ash.create!(Project, %{name: "last-updated-test", pattern: "^last-updated-test"})

      # Session with older source_modified_at
      older_session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/test-older",
          cwd: "/home/user/project",
          project_id: project.id,
          started_at: ~U[2026-01-10 10:00:00Z],
          source_modified_at: ~U[2026-01-10 12:00:00Z]
        })

      # Session with newer source_modified_at
      newer_session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/test-newer",
          cwd: "/home/user/project",
          project_id: project.id,
          started_at: ~U[2026-01-09 08:00:00Z],
          source_modified_at: ~U[2026-01-11 15:00:00Z]
        })

      %{project: project, older_session: older_session, newer_session: newer_session}
    end

    test "renders Last updated header instead of Started", %{project: _project} do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "Last updated"
    end

    test "session rows are ordered by last updated descending", %{
      project: project,
      older_session: older,
      newer_session: newer
    } do
      {:ok, view, _html} = live(build_conn(), "/")

      # Select the correct project
      html =
        view
        |> element(~s{button[phx-click="filter_project"][phx-value-project-id="#{project.id}"]})
        |> render_click()

      newer_id = to_string(newer.session_id)
      older_id = to_string(older.session_id)

      newer_pos = :binary.match(html, newer_id)
      older_pos = :binary.match(html, older_id)

      assert newer_pos != :nomatch, "newer session_id not found in HTML"
      assert older_pos != :nomatch, "older session_id not found in HTML"

      # newer source_modified_at should appear first (earlier position in HTML)
      assert elem(newer_pos, 0) < elem(older_pos, 0)
    end
  end
end
