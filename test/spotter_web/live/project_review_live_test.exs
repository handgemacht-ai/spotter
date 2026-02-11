defmodule SpotterWeb.ProjectReviewLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
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

  describe "mount" do
    test "renders project review page with open annotations" do
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
      {:ok, _view, html} = live(conn, "/projects/#{project.id}/review")

      assert html =~ "Review: #{project.name}"
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
      {:ok, _view, html} = live(conn, "/projects/#{project.id}/review")

      assert html =~ "Transcript"
      assert html =~ "1 messages"
      assert html =~ "transcript text"
    end

    test "shows empty state when no open annotations" do
      {project, _session} = create_project_with_session()

      conn = build_conn()
      {:ok, _view, html} = live(conn, "/projects/#{project.id}/review")

      assert html =~ "No open annotations for this project."
    end

    test "handles invalid project id gracefully" do
      conn = build_conn()
      {:ok, _view, html} = live(conn, "/projects/#{Ash.UUID.generate()}/review")

      assert html =~ "Project not found"
      assert html =~ "does not exist"
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
      {:ok, _view, html} = live(conn, "/projects/#{project.id}/review")

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
      {:ok, view, _html} = live(conn, "/projects/#{project.id}/review")

      html = render_click(view, "close_review_session")

      assert html =~ "Closed 2 annotations"
      assert html =~ "No open annotations for this project."
    end

    test "shows zero count when no open annotations exist" do
      {project, _session} = create_project_with_session()

      conn = build_conn()
      {:ok, view, _html} = live(conn, "/projects/#{project.id}/review")

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
      {:ok, view, _html} = live(conn, "/projects/#{project.id}/review")

      html = render_click(view, "close_review_session")

      assert html =~ "Closed 1 annotations"
    end
  end

  describe "open_conversation" do
    test "attempts to launch review tmux session and shows flash" do
      {project, session} = create_project_with_session()

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "review me",
        comment: "annotation"
      })

      conn = build_conn()
      {:ok, view, _html} = live(conn, "/projects/#{project.id}/review")

      html = render_click(view, "open_conversation")

      # In test, tmux may not be available, so we accept either success or failure flash
      assert html =~ "review session" or html =~ "Failed to launch"
    end
  end
end
