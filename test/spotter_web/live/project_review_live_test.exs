defmodule SpotterWeb.ProjectReviewLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Annotation, Message, Project, Session, Subagent}

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

      # Invalid project falls back — with no projects, shows empty state
      assert html =~ "Reviews"
      assert html =~ "No project selected."
    end

    test "shows closed annotations in resolved section" do
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
      assert html =~ "closed one"
      assert html =~ "Resolved annotations"
      assert html =~ "resolved-section"
    end

    test "resolved annotation with resolution note renders it" do
      {project, session} = create_project_with_session()

      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          selected_text: "resolved one",
          comment: "review this"
        })

      Ash.update!(
        ann,
        %{resolution: "Fixed the bug in controller", resolution_kind: :code_change},
        action: :resolve
      )

      conn = build_conn()
      {:ok, _view, html} = live(conn, reviews_path(project))

      assert html =~ "Resolution note:"
      assert html =~ "Fixed the bug in controller"
      assert html =~ "code_change"
    end

    test "resolved annotation without resolution metadata shows missing" do
      {project, session} = create_project_with_session()

      ann =
        Ash.create!(Annotation, %{
          session_id: session.id,
          selected_text: "legacy closed",
          comment: "old"
        })

      # Close via :close action (no resolution metadata)
      Ash.update!(ann, %{}, action: :close)

      conn = build_conn()
      {:ok, _view, html} = live(conn, reviews_path(project))

      assert html =~ "Resolution note:"
      assert html =~ "(missing)"
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

  describe "explain annotations excluded" do
    test "explain annotations do not appear in project review" do
      {project, session} = create_project_with_session()

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "explain-hidden",
        comment: "explain",
        purpose: :explain
      })

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "review-visible",
        comment: "review",
        purpose: :review
      })

      {:ok, _view, html} = live(build_conn(), reviews_path(project))

      assert html =~ "review-visible"
      refute html =~ "explain-hidden"
    end

    test "close_review_session does not close explain annotations" do
      {project, session} = create_project_with_session()

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "review me",
        comment: "review",
        purpose: :review
      })

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "explain me",
        comment: "explain",
        purpose: :explain
      })

      {:ok, view, _html} = live(build_conn(), reviews_path(project))
      html = render_click(view, "close_review_session")

      assert html =~ "Closed 1 annotations"
    end
  end

  describe "mcp review instructions" do
    test "shows instruction panel when project has annotations" do
      {project, session} = create_project_with_session()

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "review me",
        comment: "annotation"
      })

      {:ok, _view, html} = live(build_conn(), reviews_path(project))

      assert html =~ "Run this review in Claude Code"
      assert html =~ "spotter-review"
    end
  end

  describe "subagent annotations" do
    test "shows subagent badge and link for subagent-scoped annotation" do
      {project, session} = create_project_with_session()

      subagent =
        Ash.create!(Subagent, %{
          agent_id: "task-agent-xyz",
          slug: "code-review",
          session_id: session.id
        })

      Ash.create!(Annotation, %{
        session_id: session.id,
        subagent_id: subagent.id,
        selected_text: "subagent text",
        comment: "from agent"
      })

      {:ok, _view, html} = live(build_conn(), reviews_path(project))

      assert html =~ "Subagent"
      assert html =~ "code-review"
      assert html =~ "View agent"
      assert html =~ "/sessions/#{session.session_id}/agents/task-agent-xyz"
    end

    test "session annotation does not show subagent badge" do
      {project, session} = create_project_with_session()

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "main session",
        comment: "no agent"
      })

      {:ok, _view, html} = live(build_conn(), reviews_path(project))

      assert html =~ "View session"
      refute html =~ "Subagent"
    end
  end
end
