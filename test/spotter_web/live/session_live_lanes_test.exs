defmodule SpotterWeb.SessionLiveLanesTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Message, Project, Session, Team, TeamMember}

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "test-lanes", pattern: "^test"})
    session_id = Ash.UUID.generate()

    session =
      Ash.create!(Session, %{
        session_id: session_id,
        transcript_dir: "/tmp/test-sessions",
        cwd: "/home/user/project",
        project_id: project.id,
        message_count: 1
      })

    %{project: project, session: session, session_id: session_id}
  end

  defp create_message(session, attrs) do
    defaults = %{
      uuid: Ash.UUID.generate(),
      type: :assistant,
      role: :assistant,
      timestamp: DateTime.utc_now(),
      session_id: session.id
    }

    Ash.create!(Message, Map.merge(defaults, attrs))
  end

  defp setup_team_session(project, session) do
    # Update session with team fields
    session = Ash.update!(session, %{team_name: "test-team", agent_name: "team-lead"})

    # Create Team and TeamMember
    team = Ash.create!(Team, %{name: "test-team", project_id: project.id})

    _member =
      Ash.create!(TeamMember, %{
        agent_name: "team-lead",
        team_id: team.id,
        session_id: session.id
      })

    {session, team}
  end

  describe "view mode toggle" do
    test "default view mode is :list — renders transcript_panel, not lanes_panel", %{
      session: session,
      session_id: session_id
    } do
      create_message(session, %{
        content: %{"blocks" => [%{"type" => "text", "text" => "Hello"}]}
      })

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      # Transcript panel should be visible
      assert html =~ ~s(data-testid="transcript-container")
      assert html =~ "session-transcript"

      # Lanes panel should NOT be visible
      refute html =~ "lanes-container"
      refute html =~ "lanes-panel"
    end

    test "toggle button not shown when session has no team_name", %{
      session_id: session_id
    } do
      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      refute html =~ ~s(phx-click="switch_view_mode")
      refute html =~ ~s(data-testid="view-mode-toggle")
    end

    test "toggle button shown when session has team_name", %{
      project: project,
      session: session,
      session_id: session_id
    } do
      {_session, _team} = setup_team_session(project, session)

      {:ok, _view, html} = live(build_conn(), "/sessions/#{session_id}")

      assert html =~ ~s(data-testid="view-mode-toggle")
      assert html =~ "Lanes"
      assert html =~ "List"
    end

    test "clicking Lanes switches to lanes view and renders lanes_panel", %{
      project: project,
      session: session,
      session_id: session_id
    } do
      {_session, _team} = setup_team_session(project, session)

      {:ok, view, _html} = live(build_conn(), "/sessions/#{session_id}")

      html = render_click(view, "switch_view_mode", %{"mode" => "lanes"})

      # Lanes panel should now be visible
      assert html =~ "lanes-container"

      # Transcript panel should NOT be visible
      refute html =~ ~s(id="transcript-panel")
    end

    test "clicking List switches back to list view and renders transcript_panel", %{
      project: project,
      session: session,
      session_id: session_id
    } do
      {_session, _team} = setup_team_session(project, session)

      {:ok, view, _html} = live(build_conn(), "/sessions/#{session_id}")

      # Switch to lanes first
      render_click(view, "switch_view_mode", %{"mode" => "lanes"})

      # Switch back to list
      html = render_click(view, "switch_view_mode", %{"mode" => "list"})

      # Transcript panel should be visible again
      assert html =~ ~s(id="transcript-panel")
      assert html =~ ~s(data-testid="transcript-container")

      # Lanes panel should NOT be visible
      refute html =~ "lanes-container"
    end

    test "lanes mode renders lane data from ParallelLanes.compute/1", %{
      project: project,
      session: session,
      session_id: session_id
    } do
      {_session, team} = setup_team_session(project, session)

      # Add a second team member with its own session and messages
      second_session_id = Ash.UUID.generate()

      second_session =
        Ash.create!(Session, %{
          session_id: second_session_id,
          transcript_dir: "/tmp/test-sessions",
          cwd: "/home/user/project",
          project_id: project.id,
          team_name: "test-team",
          agent_name: "qa-tester",
          message_count: 1
        })

      Ash.create!(TeamMember, %{
        agent_name: "qa-tester",
        team_id: team.id,
        session_id: second_session.id
      })

      # Create messages for both sessions so lanes have content
      create_message(session, %{
        content: %{"blocks" => [%{"type" => "text", "text" => "Lead message"}]},
        timestamp: ~U[2026-02-20 10:00:00Z]
      })

      create_message(second_session, %{
        content: %{"blocks" => [%{"type" => "text", "text" => "QA message"}]},
        timestamp: ~U[2026-02-20 10:05:00Z]
      })

      {:ok, view, _html} = live(build_conn(), "/sessions/#{session_id}")

      html = render_click(view, "switch_view_mode", %{"mode" => "lanes"})

      # Should render lane columns for both agents
      assert html =~ "lanes-container"
      assert html =~ "team-lead"
      assert html =~ "qa-tester"
      assert html =~ "lanes-column"
    end
  end
end
