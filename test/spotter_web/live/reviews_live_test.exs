defmodule SpotterWeb.ReviewsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Annotation, Project, Session, Subagent}

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_session(project) do
    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "test-dir",
      project_id: project.id
    })
  end

  defp create_annotation(session, state, opts \\ []) do
    Ash.create!(Annotation, %{
      session_id: session.id,
      selected_text: Keyword.get(opts, :text, "text-#{System.unique_integer([:positive])}"),
      comment: "comment",
      state: state,
      purpose: Keyword.get(opts, :purpose, :review)
    })
  end

  describe "page structure" do
    test "renders heading and filter label" do
      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "<h1>Reviews</h1>"
      assert html =~ "Project"
    end

    test "renders All chip with total count" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)
      create_annotation(session, :open)
      create_annotation(session, :closed)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "All (2)"
    end

    test "renders per-project chips with name and count" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")

      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      create_annotation(sess_a, :open)
      create_annotation(sess_b, :open)
      create_annotation(sess_b, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "alpha (1)"
      assert html =~ "beta (2)"
    end

    test "renders All (0) when no projects exist" do
      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "All (0)"
    end

    test "includes project with zero open annotations in chips" do
      proj_a = create_project("alpha")
      create_project("beta")

      sess_a = create_session(proj_a)
      create_annotation(sess_a, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "alpha (1)"
      assert html =~ "beta (0)"
    end
  end

  describe "all-project mode" do
    test "hides action buttons and helper text" do
      {:ok, _view, html} = live(build_conn(), "/reviews")

      refute html =~ "Select a project to open or close a review session."
      refute html =~ "Run this review in Claude Code"
      refute html =~ "Close review session"
    end

    test "renders project section headers with open counts" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")
      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      create_annotation(sess_a, :open)
      create_annotation(sess_b, :open)
      create_annotation(sess_b, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "alpha"
      assert html =~ "(1 open)"
      assert html =~ "beta"
      assert html =~ "(2 open)"
    end

    test "renders annotations under their respective project sections" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")
      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      ann_a = create_annotation(sess_a, :open)
      ann_b = create_annotation(sess_b, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      # Both annotations appear in the page
      assert html =~ ann_a.selected_text
      assert html =~ ann_b.selected_text

      # Both project sections exist
      assert html =~ "project-section"
    end

    test "shows section-level empty state for project with zero annotations" do
      proj_a = create_project("alpha")
      create_project("beta")
      sess_a = create_session(proj_a)
      create_annotation(sess_a, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "alpha"
      assert html =~ "beta"
      assert html =~ "No open annotations."
    end
  end

  describe "project-scoped mode" do
    test "shows action buttons in project mode" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "Run this review in Claude Code"
      assert html =~ "Close review session"
    end

    test "renders empty state when project has no open annotations" do
      project = create_project("alpha")

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "No open annotations for the selected scope."
    end

    test "excludes closed annotations" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :closed)

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "No open annotations for the selected scope."
    end
  end

  describe "project chip navigation" do
    test "clicking a project chip updates URL and filters" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")
      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      create_annotation(sess_a, :open)
      create_annotation(sess_b, :open)

      {:ok, view, _html} = live(build_conn(), "/reviews")

      # Click project alpha chip
      html =
        render_click(view, "filter_project", %{"project-id" => proj_a.id})

      # Should show alpha's annotation and action buttons
      assert html =~ "Run this review in Claude Code"
      assert_patched(view, "/reviews?project_id=#{proj_a.id}")
    end

    test "clicking All chip returns to all-project mode" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      html = render_click(view, "filter_project", %{"project-id" => "all"})

      refute html =~ "Run this review in Claude Code"
      refute html =~ "Close review session"
      assert_patched(view, "/reviews")
    end
  end

  describe "invalid project_id" do
    test "falls back to all-project mode" do
      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{Ash.UUID.generate()}")

      refute html =~ "Select a project to open or close a review session."
      refute html =~ "Run this review in Claude Code"
      refute html =~ "Close review session"
    end

    test "does not crash with non-UUID value" do
      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=bogus")

      assert html =~ "Reviews"
    end
  end

  describe "explain annotations excluded" do
    test "explain annotations do not appear in project-scoped view" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open, purpose: :explain, text: "explain-only-text")
      create_annotation(session, :open, purpose: :review, text: "review-only-text")

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "review-only-text"
      refute html =~ "explain-only-text"
    end

    test "explain annotations are not counted in project chips" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open, purpose: :review)
      create_annotation(session, :open, purpose: :explain)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "All (1)"
      assert html =~ "alpha (1)"
    end

    test "close_review_session does not close explain annotations" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open, purpose: :review)
      create_annotation(session, :open, purpose: :explain)

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{project.id}")
      html = render_click(view, "close_review_session")

      assert html =~ "Closed 1 annotations"
    end
  end

  describe "sidebar badge" do
    test "shows badge with positive count" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      conn = build_conn() |> get("/reviews")
      html = html_response(conn, 200)

      assert html =~ "sidebar-badge"
      assert html =~ "data-reviews-badge"
      refute html =~ "display:none;"
    end

    test "hides badge when count is zero" do
      conn = build_conn() |> get("/reviews")
      html = html_response(conn, 200)

      assert html =~ "data-reviews-badge"
      assert html =~ "display:none;"
    end
  end

  describe "subagent annotations" do
    test "shows subagent badge and slug for subagent-scoped annotation" do
      project = create_project("alpha")
      session = create_session(project)

      subagent =
        Ash.create!(Subagent, %{
          agent_id: "task-agent-abc",
          slug: "task-runner",
          session_id: session.id
        })

      Ash.create!(Annotation, %{
        session_id: session.id,
        subagent_id: subagent.id,
        selected_text: "agent output",
        comment: "from subagent"
      })

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "Subagent"
      assert html =~ "task-runner"
      assert html =~ "View agent"
      assert html =~ "/sessions/#{session.session_id}/agents/task-agent-abc"
    end

    test "shows short agent_id when slug is nil" do
      project = create_project("alpha")
      session = create_session(project)

      subagent =
        Ash.create!(Subagent, %{
          agent_id: "abcdef1234567890",
          session_id: session.id
        })

      Ash.create!(Annotation, %{
        session_id: session.id,
        subagent_id: subagent.id,
        selected_text: "agent output",
        comment: "no slug"
      })

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "Subagent"
      assert html =~ "abcdef12"
    end

    test "session annotation shows View session link" do
      project = create_project("alpha")
      session = create_session(project)

      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "session text",
        comment: "main session"
      })

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "View session"
      refute html =~ "Subagent"
    end
  end
end
