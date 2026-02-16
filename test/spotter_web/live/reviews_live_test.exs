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

    test "shows No project selected when no projects exist" do
      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "No project selected."
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

  describe "auto-select first project" do
    test "auto-selects first project and shows action buttons" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      # Auto-selects first project, so action buttons visible
      assert html =~ "Run this review in Claude Code"
      assert html =~ "Close review session"
    end

    test "shows annotations for auto-selected project" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")
      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      ann_a = create_annotation(sess_a, :open)
      _ann_b = create_annotation(sess_b, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      # Auto-selects first project (alpha), so only alpha's annotations appear
      assert html =~ ann_a.selected_text
    end

    test "shows empty state when auto-selected project has no annotations" do
      create_project("alpha")

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "No open annotations for the selected scope."
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

    test "shows closed annotations in resolved section" do
      project = create_project("alpha")
      session = create_session(project)
      ann = create_annotation(session, :open, text: "will-resolve")

      Ash.update!(ann, %{resolution: "Fixed it", resolution_kind: :code_change}, action: :resolve)

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "Resolved annotations"
      assert html =~ "will-resolve"
      assert html =~ "Resolution note:"
      assert html =~ "Fixed it"
    end

    test "resolved annotations do not appear for a different project" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")
      session = create_session(proj_a)
      ann = create_annotation(session, :open, text: "resolved-hidden")

      Ash.update!(ann, %{resolution: "Done"}, action: :resolve)

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{proj_b.id}")

      refute html =~ "Resolved annotations"
      refute html =~ "resolved-hidden"
    end

    test "project chips counts are based on open annotations only" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open, text: "open-one")
      ann = create_annotation(session, :open, text: "will-close")

      Ash.update!(ann, %{resolution: "Done"}, action: :resolve)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "alpha (1)"
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

    test "clicking a different project chip switches project" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")
      sess_a = create_session(proj_a)
      sess_b = create_session(proj_b)

      create_annotation(sess_a, :open)
      create_annotation(sess_b, :open)

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{proj_a.id}")

      html = render_click(view, "filter_project", %{"project-id" => proj_b.id})

      assert html =~ "Run this review in Claude Code"
      assert_patched(view, "/reviews?project_id=#{proj_b.id}")
    end
  end

  describe "invalid project_id" do
    test "falls back to first project" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{Ash.UUID.generate()}")

      # Invalid project falls back to first project, so action buttons visible
      assert html =~ "Run this review in Claude Code"
      assert html =~ "Close review session"
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

  describe "unbound file annotations" do
    test "unbound file annotations appear in project review" do
      project = create_project("alpha")

      Ash.create!(Annotation, %{
        source: :file,
        selected_text: "unbound-file-text",
        comment: "unbound review",
        project_id: project.id,
        purpose: :review
      })

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "unbound-file-text"
    end

    test "unbound file annotations counted in project chips" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      Ash.create!(Annotation, %{
        source: :file,
        selected_text: "unbound",
        comment: "unbound",
        project_id: project.id,
        purpose: :review
      })

      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "alpha (2)"
    end

    test "unbound file annotations do not leak across projects" do
      proj_a = create_project("alpha")
      proj_b = create_project("beta")

      Ash.create!(Annotation, %{
        source: :file,
        selected_text: "alpha-only-unbound",
        comment: "unbound",
        project_id: proj_a.id,
        purpose: :review
      })

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{proj_b.id}")

      refute html =~ "alpha-only-unbound"
    end

    test "close_review_session closes unbound file annotations" do
      project = create_project("alpha")

      Ash.create!(Annotation, %{
        source: :file,
        selected_text: "unbound-close",
        comment: "will close",
        project_id: project.id,
        purpose: :review
      })

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
