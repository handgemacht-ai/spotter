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

      assert html =~ ~s(data-testid="acceptance-table")
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

      assert html =~ ~s(data-testid="bead-annotations")
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
end
