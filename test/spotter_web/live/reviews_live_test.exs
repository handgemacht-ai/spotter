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

    # Clean pre-existing data so tests don't depend on empty DB
    Repo.query!("DELETE FROM annotations")
    Repo.query!("DELETE FROM sessions")
    Repo.query!("DELETE FROM projects")

    :ok
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
    test "renders heading" do
      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "<h1>Reviews</h1>"
    end

    test "shows No project selected when no projects exist" do
      {:ok, _view, html} = live(build_conn(), "/reviews")

      assert html =~ "No project selected."
    end
  end

  describe "auto-select first project" do
    test "auto-selects first project and shows action buttons" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews")

      # Auto-selects first project, so action buttons visible
      assert html =~ "Review in Claude Code"
      assert html =~ "/spotter-review"
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

      assert html =~ "Review in Claude Code"
      assert html =~ "/spotter-review"
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
  end

  describe "project context from on_mount" do
    test "uses current_project_id from on_mount, no project filter chips" do
      project = create_project("ctx-proj")
      session = create_session(project)
      create_annotation(session, :open, text: "ctx-annotation")

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      # Content is filtered by on_mount current_project_id
      assert html =~ "ctx-annotation"

      # No project filter chips — project selection is in the sidebar now
      refute html =~ "filter_project"
    end
  end

  describe "invalid project_id" do
    test "falls back to first project" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{Ash.UUID.generate()}")

      # Invalid project falls back to first project, so action buttons visible
      assert html =~ "Review in Claude Code"
      assert html =~ "/spotter-review"
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

    test "explain annotations are excluded from open count" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open, purpose: :review)
      create_annotation(session, :open, purpose: :explain)

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "1 open annotations"
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

    test "unbound file annotations counted in open annotations" do
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

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "2 open annotations"
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

  describe "single annotation delete" do
    test "shows delete button on open annotation cards" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open, text: "deletable-open")

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "deletable-open"
      assert html =~ "Delete"
    end

    test "shows delete button on resolved annotation cards" do
      project = create_project("alpha")
      session = create_session(project)
      ann = create_annotation(session, :open, text: "deletable-resolved")
      Ash.update!(ann, %{resolution: "Done"}, action: :resolve)

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "deletable-resolved"
      assert html =~ "Delete"
    end

    test "clicking delete shows confirmation modal" do
      project = create_project("alpha")
      session = create_session(project)
      ann = create_annotation(session, :open, text: "confirm-me")

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      html = render_click(view, "delete_annotation", %{"id" => ann.id})

      assert html =~ "Delete this annotation?"
      assert html =~ "This action cannot be undone."
    end

    test "confirming delete removes the annotation" do
      project = create_project("alpha")
      session = create_session(project)
      ann = create_annotation(session, :open, text: "bye-bye")

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      render_click(view, "delete_annotation", %{"id" => ann.id})
      html = render_click(view, "confirm_delete")

      assert html =~ "Annotation deleted"
      refute html =~ "bye-bye"
    end

    test "cancelling delete keeps the annotation" do
      project = create_project("alpha")
      session = create_session(project)
      ann = create_annotation(session, :open, text: "keep-me")

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      render_click(view, "delete_annotation", %{"id" => ann.id})
      html = render_click(view, "cancel_delete")

      refute html =~ "Delete this annotation?"
      assert html =~ "keep-me"
    end

    test "escape key closes confirmation modal" do
      project = create_project("alpha")
      session = create_session(project)
      ann = create_annotation(session, :open, text: "escape-test")

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      render_click(view, "delete_annotation", %{"id" => ann.id})
      html = render_click(view, "keydown", %{"key" => "Escape"})

      refute html =~ "Delete this annotation?"
      assert html =~ "escape-test"
    end
  end

  describe "batch selection and delete" do
    test "shows select button in page header" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open)

      {:ok, _view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "Select"
    end

    test "entering selection mode shows checkboxes" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open, text: "selectable")

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      html = view |> element("[phx-click=enter_selection_mode]") |> render_click()

      assert html =~ "Cancel"
      assert html =~ "checkbox"
    end

    test "selecting annotations shows batch action bar" do
      project = create_project("alpha")
      session = create_session(project)
      ann = create_annotation(session, :open, text: "select-me")

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      render_click(view, "enter_selection_mode")
      html = render_click(view, "toggle_select", %{"id" => ann.id})

      assert html =~ "1 selected"
      assert html =~ "Delete selected"
    end

    test "batch delete with confirmation removes all selected annotations" do
      project = create_project("alpha")
      session = create_session(project)
      ann1 = create_annotation(session, :open, text: "batch-one")
      ann2 = create_annotation(session, :open, text: "batch-two")
      _ann3 = create_annotation(session, :open, text: "batch-keep")

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      render_click(view, "enter_selection_mode")
      render_click(view, "toggle_select", %{"id" => ann1.id})
      render_click(view, "toggle_select", %{"id" => ann2.id})
      render_click(view, "batch_delete")

      assert render(view) =~ "Delete 2 annotations?"

      html = render_click(view, "confirm_delete")

      assert html =~ "2 annotations deleted"
      refute html =~ "batch-one"
      refute html =~ "batch-two"
      assert html =~ "batch-keep"
    end

    test "exiting selection mode clears selections" do
      project = create_project("alpha")
      session = create_session(project)
      ann = create_annotation(session, :open, text: "exit-select")

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      render_click(view, "enter_selection_mode")
      render_click(view, "toggle_select", %{"id" => ann.id})
      html = render_click(view, "exit_selection_mode")

      refute html =~ "selected"
      assert html =~ "Select"
    end

    test "deselect all clears selection count" do
      project = create_project("alpha")
      session = create_session(project)
      ann = create_annotation(session, :open, text: "deselect-me")

      {:ok, view, _html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      render_click(view, "enter_selection_mode")
      render_click(view, "toggle_select", %{"id" => ann.id})
      html = render_click(view, "deselect_all")

      refute html =~ "Delete selected"
    end

    test "delete button hidden in selection mode" do
      project = create_project("alpha")
      session = create_session(project)
      create_annotation(session, :open, text: "hidden-delete")

      {:ok, view, html} = live(build_conn(), "/reviews?project_id=#{project.id}")

      assert html =~ "Delete"

      html = view |> element("[phx-click=enter_selection_mode]") |> render_click()

      refute html =~ "phx-click=\"delete_annotation\""
    end
  end
end
