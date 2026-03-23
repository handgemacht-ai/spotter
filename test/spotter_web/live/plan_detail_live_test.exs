defmodule SpotterWeb.PlanDetailLiveTest do
  @moduledoc """
  Integration tests for PlanDetailLive — the bead detail view.

  Route: /plans/:project/:bead_id
  Tests: parsed sections, mermaid hooks, acceptance table,
         child tasks, dependencies, annotations, classification,
         graceful degradation, back navigation.
  """
  use Spotter.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Spotter.Transcripts.{Annotation, Project}

  @endpoint SpotterWeb.Endpoint

  describe "mount with bead data" do
    test "renders bead detail view with title and badges" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="bead-detail")
      assert html =~ ~s(data-testid="bead-detail-header")
      assert html =~ "data-status="
      assert html =~ "data-priority="
    end
  end

  describe "description sections" do
    test "renders parsed sections from BeadContentParser" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      # Sections container must exist
      assert html =~ ~s(data-testid="bead-sections")
      # Individual section headings rendered as h3 elements
      assert html =~ ~s(data-testid="section-heading")
    end
  end

  describe "mermaid diagram rendering" do
    test "wraps mermaid blocks with phx-hook and data attribute" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      # Mermaid blocks must be rendered as hook-compatible elements
      assert html =~ "phx-hook=\"MermaidHook\""
      assert html =~ "data-mermaid-source="
    end
  end

  describe "acceptance criteria table" do
    test "renders GIVEN/WHEN/THEN table from parsed description" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="acceptance-cards")
      # Table headers
      assert html =~ "GIVEN"
      assert html =~ "WHEN"
      assert html =~ "THEN"
    end
  end

  describe "child tasks" do
    test "lists child tasks with id, title, status, and priority" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="child-tasks")
      assert html =~ ~s(data-testid="child-task-row")
    end

    test "child task rows are navigable links" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="child-task-row")
      refute html =~ "toggle_task"
    end
  end

  describe "text selection annotation" do
    setup do
      project = Ash.create!(Project, %{name: "beads_spotter", pattern: "^beads_spotter"})

      %{project: project}
    end

    test "plan_text_selected event creates annotation with source=:plan and bead_id", %{
      project: project
    } do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      render_click(view, "plan_text_selected", %{
        "selected_text" => "Plans Navigation feature",
        "comment" => "Review this section"
      })

      html = render(view)

      # Selection state should be visible
      assert html =~ "Plans Navigation feature"

      # Annotation created in database with plan source
      annotations = Ash.read!(Annotation)
      plan_annotation = Enum.find(annotations, &(&1.source == :plan))
      assert plan_annotation
      assert plan_annotation.bead_id == "spotter-uok"
      assert plan_annotation.selected_text == "Plans Navigation feature"
      assert plan_annotation.project_id == project.id
    end

    test "clear_selection event resets selection state" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      render_click(view, "plan_text_selected", %{
        "selected_text" => "some text",
        "comment" => "note"
      })

      html = render_click(view, "clear_selection", %{})
      refute html =~ ~s(data-testid="selection-active")
    end
  end

  describe "bead-centric data loading" do
    test "loads and renders dependencies section" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="bead-dependencies")
    end
  end

  describe "expanded_tasks removal" do
    test "toggle_task event is no longer handled" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      refute html =~ "toggle_task"
    end
  end

  describe "bead-centric template" do
    test "renders bead-detail data-testid instead of epic-detail" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="bead-detail")
      refute html =~ ~s(data-testid="epic-detail")
    end
  end

  describe "annotations loading" do
    setup do
      project = Ash.create!(Project, %{name: "beads_spotter", pattern: "^beads_spotter"})

      Ash.create!(Annotation, %{
        source: :plan,
        bead_id: "spotter-uok",
        selected_text: "pre-existing annotation",
        comment: "loaded in handle_params",
        purpose: :review,
        project_id: project.id
      })

      %{project: project}
    end

    test "handle_params loads existing annotations for the bead" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="plan-detail-sidebar")
    end
  end

  describe "content parsing with classification" do
    test "sections include type classification from BeadContentParser" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-section-type=)
    end
  end

  describe "graceful degradation" do
    test "shows friendly empty state when Dolt is unavailable" do
      # This test exercises the path where BeadQueries return errors
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/nonexistent-epic-xyz")

      html = render(view)

      assert html =~ "empty-state" or html =~ "not found" or html =~ "unavailable"
    end
  end

  describe "back navigation" do
    test "has link back to plans list preserving project context" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(href="/plans?project=beads_spotter") or
               html =~ ~s(data-testid="back-to-plans")
    end
  end

  describe "PlanContentHook replaces PlanHighlighter" do
    test "sections container uses PlanContentHook hook instead of PlanHighlighter" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(phx-hook="PlanContentHook")
      refute html =~ ~s(phx-hook="PlanHighlighter")
    end
  end

  describe "section type filtering" do
    test "narrative sections render headings, acceptance sections do not" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      # The fixture has an "Acceptance Criteria" section (type=acceptance).
      # Acceptance content is handled by the dedicated <.acceptance_table> component,
      # so the sections loop should skip acceptance-type sections entirely
      # (no heading, no section div for acceptance type).
      assert html =~ ~s(data-section-type="narrative")

      # Acceptance-type sections should not appear in the sections loop at all
      refute html =~ ~s(data-section-type="acceptance"),
             "acceptance sections should be skipped — handled by dedicated component"

      # Narrative sections must still have their headings
      assert html =~ ~s(data-section-type="narrative")
      assert html =~ "Overview"
      assert html =~ "Implementation Notes"
    end
  end

  describe "bead-content rendering" do
    test "narrative section bodies have bead-content class for code highlighting" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      # Narrative sections should wrap their body in bead-content for PlanContentHook highlighting
      assert html =~ ~s(class="plan-section-body bead-content")

      # The raw HTML from BeadContentParser.render_section_body should be output unescaped
      # (Earmark wraps text in <p> tags — these should appear as real HTML, not &lt;p&gt;)
      assert html =~ "<p>\nPlans Navigation feature for Spotter.</p>"
      refute html =~ "&lt;p&gt;"
    end
  end

  # ── spotter-00o: Inline annotation highlights + annotation display ────

  describe "annotations data attribute on plan-content" do
    setup do
      project = Ash.create!(Project, %{name: "beads_spotter", pattern: "^beads_spotter"})

      {:ok, ann} =
        Ash.create(Annotation, %{
          source: :plan,
          bead_id: "spotter-uok",
          selected_text: "Plans Navigation feature",
          comment: "highlight this text",
          purpose: :review,
          project_id: project.id
        })

      %{project: project, annotation: ann}
    end

    test "plan-sections div includes data-annotations JSON when annotations exist", %{
      annotation: ann
    } do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      # The PlanContentHook container must carry annotations as a JSON data attribute
      # so the JS hook can fuzzy-match and highlight annotation text inline.
      # Match the attribute on the bead-sections div specifically (not bead-annotations testid).
      assert html =~ ~r/id="plan-sections"[^>]*data-annotations="/

      # The JSON must contain the annotation's selected_text for JS highlighting
      assert html =~ "Plans Navigation feature"
      assert html =~ ann.id
    end

    test "annotation_cards component renders in bead-annotations-section" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      # Annotations section must use annotation_cards component (from AnnotationComponents)
      # with clickable cards containing source badge, selected_text, comment, and delete button
      assert html =~ ~s(class="annotation-card")
      assert html =~ "Plans Navigation feature"
      assert html =~ "highlight this text"
      assert html =~ ~s(phx-click="highlight_annotation")
    end
  end

  describe "empty annotations: section hidden, no data attribute" do
    test "plan-sections div omits data-annotations when no annotations exist" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      # Without annotations, the plan-sections div must NOT carry data-annotations
      refute html =~ ~r/id="plan-sections"[^>]*data-annotations="/
    end

    test "bead-annotations-section is hidden when no annotations" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      refute html =~ ~s(class="annotation-card")
      refute html =~ ~s(data-testid="bead-annotations-section")
    end
  end

  describe "highlight_annotation event handler" do
    setup do
      project = Ash.create!(Project, %{name: "beads_spotter", pattern: "^beads_spotter"})

      {:ok, ann} =
        Ash.create(Annotation, %{
          source: :plan,
          bead_id: "spotter-uok",
          selected_text: "Plans Navigation feature",
          comment: "highlight me",
          purpose: :review,
          project_id: project.id
        })

      %{project: project, annotation: ann}
    end

    test "highlight_annotation event sets highlighted annotation ID in assigns", %{
      annotation: ann
    } do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render_click(view, "highlight_annotation", %{"id" => ann.id})

      # After clicking an annotation card, the highlighted annotation ID should be reflected
      # in the rendered output (e.g. as an active/highlighted CSS class or data attribute)
      assert html =~ ~s(data-highlighted-annotation="#{ann.id}")
    end
  end

  # ── spotter-055: Component integration tests ──────────────────────────

  describe "bead_header/1" do
    test "renders type chip, bead ID, title, status, and priority" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      header = html
      assert header =~ ~s(data-testid="bead-type-chip")
      assert header =~ "epic"
      assert header =~ ~s(data-testid="bead-id")
      assert header =~ "spotter-uok"
      assert header =~ "Plans Navigation"
      assert header =~ "data-status="
      assert header =~ "data-priority="
    end
  end

  describe "acceptance_cards/1" do
    test "renders GIVEN/WHEN/THEN rows as card elements" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="acceptance-cards")
      assert html =~ "GIVEN"
      assert html =~ "WHEN"
      assert html =~ "THEN"
      assert html =~ "A project with epics"
      assert html =~ "User opens plans page"
      assert html =~ "Epic list is displayed"
    end
  end

  describe "classification_chips/1" do
    test "renders classification key-value pairs as badge chips" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="bead-classification")
      assert html =~ "feature"
      assert html =~ "frontend"
      assert html =~ "backend"
      assert html =~ "medium"
    end
  end

  describe "dependency_list/1" do
    test "renders navigable dependency rows with status badges" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="bead-dependencies")
      assert html =~ ~s(data-testid="dependency-row")
      assert html =~ "spotter-dep-1"
      assert html =~ "Setup Infrastructure"
      assert html =~ ~s(data-status="closed")
      assert html =~ "blocks"
      assert html =~ ~r/href="[^"]*spotter-dep-1/
    end
  end

  describe "task_row/1 navigable link" do
    test "renders task ID and title as a single navigable link" do
      {:ok, view, _html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="child-task-row")
      assert html =~ ~s(class="plan-task-link")
      assert html =~ "spotter-task-1"
      assert html =~ "Implement BeadQueries"
      assert html =~ ~r/href="[^"]*spotter-task-1/
      refute html =~ "toggle_task"
    end
  end

  describe "empty state hiding" do
    test "acceptance_cards hides when no acceptance rows" do
      {:ok, view, _html} =
        live(build_conn(), "/plans/beads_spotter/nonexistent-epic-xyz")

      html = render(view)

      refute html =~ ~s(data-testid="acceptance-cards")
    end

    test "classification_chips hides when no classification data" do
      {:ok, view, _html} =
        live(build_conn(), "/plans/beads_spotter/nonexistent-epic-xyz")

      html = render(view)

      refute html =~ ~s(data-testid="bead-classification")
    end

    test "dependency_list hides when no dependencies" do
      {:ok, view, _html} =
        live(build_conn(), "/plans/beads_spotter/nonexistent-epic-xyz")

      html = render(view)

      refute html =~ ~s(data-testid="bead-dependencies")
    end

    test "child tasks section hides when no children" do
      {:ok, view, _html} =
        live(build_conn(), "/plans/beads_spotter/nonexistent-epic-xyz")

      html = render(view)

      refute html =~ ~s(data-testid="child-tasks")
    end
  end
end
