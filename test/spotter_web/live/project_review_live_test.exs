defmodule SpotterWeb.ProjectReviewLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.TestSupport.FakeTmux
  alias Spotter.Transcripts.{Annotation, Message, Project, Session}

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project_with_session do
    project =
      Ash.create!(Project, %{
        name: "review-test-#{System.unique_integer([:positive])}",
        pattern: "^test"
      })

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

    {project, session}
  end

  defp reviews_path(project) do
    "/reviews?project_id=#{project.id}"
  end

  describe "legacy redirect" do
    test "redirects /projects/:project_id/review to /reviews?project_id=..." do
      {project, _session} = create_project_with_session()

      conn = build_conn() |> get("/projects/#{project.id}/review")

      assert redirected_to(conn) == "/reviews?project_id=#{project.id}"
    end
  end

  describe "mount" do
    test "renders reviews page with open annotations" do
      {project, session} = create_project_with_session()

      Ash.create!(Annotation, %{
        session_id: session.id,
        source: :terminal,
        selected_text: "important code",
        comment: "needs review",
        start_row: 0,
        start_col: 0,
        end_row: 0,
        end_col: 14
      })

      conn = build_conn()
      {:ok, _view, html} = live(conn, reviews_path(project))

      assert html =~ "Reviews"
      assert html =~ "important code"
      assert html =~ "needs review"
      assert html =~ "Terminal"
    end

    test "renders transcript annotation with message ref count" do
      {project, session} = create_project_with_session()

      msg =
        Ash.create!(Message, %{
          uuid: "msg-1",
          type: :user,
          role: :user,
          timestamp: DateTime.utc_now(),
          session_id: session.id,
          content: %{"text" => "hello"}
        })

      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :transcript,
          selected_text: "transcript text",
          comment: "noted"
        })

      Ash.create!(Spotter.Transcripts.AnnotationMessageRef, %{
        annotation_id: ann.id,
        message_id: msg.id,
        ordinal: 0
      })

      conn = build_conn()
      {:ok, _view, html} = live(conn, reviews_path(project))

      assert html =~ "Transcript"
      assert html =~ "1 messages"
      assert html =~ "transcript text"
    end

    test "shows empty state when no open annotations" do
      {project, _session} = create_project_with_session()

      conn = build_conn()
      {:ok, _view, html} = live(conn, reviews_path(project))

      assert html =~ "No open annotations for the selected scope."
    end

    test "handles invalid project id gracefully" do
      conn = build_conn()
      {:ok, _view, html} = live(conn, "/reviews?project_id=#{Ash.UUID.generate()}")

      # Invalid project falls back to all-projects mode
      assert html =~ "Reviews"
      assert html =~ "No open annotations for the selected scope."
    end

    test "excludes closed annotations" do
      {project, session} = create_project_with_session()

      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          selected_text: "closed one",
          comment: "done"
        })

      Ash.update!(ann, %{}, action: :close)

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "still open",
        comment: "wip"
      })

      conn = build_conn()
      {:ok, _view, html} = live(conn, reviews_path(project))

      assert html =~ "still open"
      refute html =~ "closed one"
    end
  end

  describe "close_review_session" do
    test "closes all open annotations and shows count" do
      {project, session} = create_project_with_session()

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "first",
        comment: "a"
      })

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "second",
        comment: "b"
      })

      conn = build_conn()
      {:ok, view, _html} = live(conn, reviews_path(project))

      html = render_click(view, "close_review_session")

      assert html =~ "Closed 2 annotations"
      assert html =~ "No open annotations for the selected scope."
    end

    test "shows zero count when no open annotations exist" do
      {project, _session} = create_project_with_session()

      conn = build_conn()
      {:ok, view, _html} = live(conn, reviews_path(project))

      html = render_click(view, "close_review_session")

      assert html =~ "Closed 0 annotations"
    end

    test "does not affect already-closed annotations" do
      {project, session} = create_project_with_session()

      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          selected_text: "already closed",
          comment: "done"
        })

      Ash.update!(ann, %{}, action: :close)

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "still open",
        comment: "wip"
      })

      conn = build_conn()
      {:ok, view, _html} = live(conn, reviews_path(project))

      html = render_click(view, "close_review_session")

      assert html =~ "Closed 1 annotations"
    end
  end

  describe "open_conversation" do
    @table :review_session_registry

    setup do
      FakeTmux.start_link()
      Application.put_env(:spotter, :tmux_module, FakeTmux)

      on_exit(fn ->
        Application.delete_env(:spotter, :tmux_module)
        Application.delete_env(:spotter, :fake_tmux_launch_result)
        FakeTmux.stop()
      end)
    end

    defp create_project_with_annotation do
      {project, session} = create_project_with_session()

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "review me",
        comment: "annotation"
      })

      project
    end

    test "successful launch registers session in registry" do
      session_name = "spotter-review-project-#{System.unique_integer([:positive])}"
      Application.put_env(:spotter, :fake_tmux_launch_result, {:ok, session_name})
      project = create_project_with_annotation()

      conn = build_conn()
      {:ok, view, _html} = live(conn, reviews_path(project))

      html = render_click(view, "open_conversation")

      assert html =~ "Launched review session: #{session_name}"
      assert [{^session_name, _ts}] = :ets.lookup(@table, session_name)

      :ets.delete(@table, session_name)
    end

    test "heartbeat updates registry timestamp after launch" do
      session_name = "spotter-review-project-hb-#{System.unique_integer([:positive])}"
      Application.put_env(:spotter, :fake_tmux_launch_result, {:ok, session_name})
      project = create_project_with_annotation()

      conn = build_conn()
      {:ok, view, _html} = live(conn, reviews_path(project))
      render_click(view, "open_conversation")

      [{_, ts_before}] = :ets.lookup(@table, session_name)

      Process.sleep(10)
      send(view.pid, :review_heartbeat)
      # Give the LiveView process time to handle the message
      render(view)

      [{_, ts_after}] = :ets.lookup(@table, session_name)
      assert ts_after >= ts_before

      :ets.delete(@table, session_name)
    end

    test "terminating LiveView deregisters session from registry" do
      session_name = "spotter-review-project-term-#{System.unique_integer([:positive])}"
      Application.put_env(:spotter, :fake_tmux_launch_result, {:ok, session_name})
      project = create_project_with_annotation()

      conn = build_conn()
      {:ok, view, _html} = live(conn, reviews_path(project))
      render_click(view, "open_conversation")

      assert [{^session_name, _}] = :ets.lookup(@table, session_name)

      GenServer.stop(view.pid)
      Process.sleep(50)

      assert :ets.lookup(@table, session_name) == []
    end

    test "failed launch does not register session" do
      Application.put_env(:spotter, :fake_tmux_launch_result, {:error, "no tmux"})
      project = create_project_with_annotation()

      conn = build_conn()
      {:ok, view, _html} = live(conn, reviews_path(project))

      html = render_click(view, "open_conversation")

      assert html =~ "Failed to launch"
      # No entries should have been registered for this test
      all_entries = :ets.tab2list(@table)
      refute Enum.any?(all_entries, fn {name, _} -> String.contains?(name, "project-test") end)
    end
  end
end
