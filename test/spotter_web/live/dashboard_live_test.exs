defmodule SpotterWeb.DashboardLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Project, Session}

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "dash-test", pattern: "^dash-test"})

    %{project: project}
  end

  describe "mount queries only ongoing sessions" do
    test "shows sessions with started_at set and session_ended_at nil", %{project: project} do
      ongoing =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/ongoing",
          cwd: "/home/user/ongoing",
          project_id: project.id,
          started_at: DateTime.utc_now()
        })

      _ended =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/ended",
          cwd: "/home/user/ended",
          project_id: project.id,
          started_at: DateTime.utc_now(),
          session_ended_at: DateTime.utc_now()
        })

      _no_start =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/nostart",
          cwd: "/home/user/nostart",
          project_id: project.id
        })

      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ongoing.session_id
      refute html =~ "ended"
      refute html =~ "nostart"
    end
  end

  describe "hidden ongoing sessions" do
    test "includes hidden sessions and labels them", %{project: project} do
      hidden =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/sess-a",
          cwd: "/home/user/project-a",
          project_id: project.id,
          started_at: DateTime.utc_now()
        })

      Ash.update!(hidden, %{}, action: :hide)

      visible =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/sess-b",
          cwd: "/home/user/project-b",
          project_id: project.id,
          started_at: DateTime.utc_now()
        })

      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ hidden.session_id
      assert html =~ visible.session_id

      [row_html] = Regex.run(~r/data-session-id="#{hidden.session_id}".*?<\/tr>/s, html)
      assert row_html =~ "badge" and row_html =~ "hidden"
    end
  end

  describe "PubSub session_activity :started" do
    test "new session appears live after broadcast", %{project: project} do
      {:ok, view, _html} = live(build_conn(), "/")

      new_id = Ash.UUID.generate()

      Ash.create!(Session, %{
        session_id: new_id,
        transcript_dir: "/tmp/new-sess",
        cwd: "/home/user/new-project",
        project_id: project.id,
        started_at: DateTime.utc_now()
      })

      Phoenix.PubSub.broadcast!(
        Spotter.PubSub,
        "session_activity",
        {:session_activity, %{session_id: new_id, status: :started}}
      )

      html = render(view)

      assert html =~ ~s(data-session-id="#{new_id}")
    end
  end

  describe "PubSub session_activity :finished" do
    test "marks ongoing row as finished in-memory", %{project: project} do
      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/finish-test",
          cwd: "/home/user/finish-project",
          project_id: project.id,
          started_at: DateTime.utc_now()
        })

      {:ok, view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-session-id="#{session.session_id}")
      [row_html] = Regex.run(~r/data-session-id="#{session.session_id}".*?<\/tr>/s, html)
      assert row_html =~ "active"
      refute row_html =~ "finished"

      Phoenix.PubSub.broadcast!(
        Spotter.PubSub,
        "session_activity",
        {:session_activity, %{session_id: session.session_id, status: :finished}}
      )

      html = render(view)

      [row_html] = Regex.run(~r/data-session-id="#{session.session_id}".*?<\/tr>/s, html)
      assert row_html =~ "finished"
      assert row_html =~ "dashboard-row-finished"
    end
  end

  describe "refresh clears finished rows" do
    test "finished rows disappear after refresh", %{project: project} do
      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/refresh-test",
          cwd: "/home/user/refresh-project",
          project_id: project.id,
          started_at: DateTime.utc_now()
        })

      {:ok, view, _html} = live(build_conn(), "/")

      # Mark as finished via PubSub
      Phoenix.PubSub.broadcast!(
        Spotter.PubSub,
        "session_activity",
        {:session_activity, %{session_id: session.session_id, status: :finished}}
      )

      html = render(view)
      [row_html] = Regex.run(~r/data-session-id="#{session.session_id}".*?<\/tr>/s, html)
      assert row_html =~ "finished"

      # Now mark session_ended_at in DB (simulating finalizer completed)
      Ash.update!(session, %{session_ended_at: DateTime.utc_now()})

      # Refresh should re-query ongoing only, clearing finished rows
      html = render_click(view, "refresh")

      refute html =~ ~s(data-session-id="#{session.session_id}")
    end
  end

  describe "ended_at alone does not mark row finished" do
    test "session with ended_at but no session_ended_at remains active", %{project: project} do
      session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/endedat-test",
          cwd: "/home/user/endedat-project",
          project_id: project.id,
          started_at: DateTime.utc_now(),
          ended_at: DateTime.utc_now()
        })

      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-session-id="#{session.session_id}")

      [row_html] = Regex.run(~r/data-session-id="#{session.session_id}".*?<\/tr>/s, html)
      assert row_html =~ "active"
      refute row_html =~ "finished"
      refute row_html =~ "dashboard-row-finished"
    end
  end
end
