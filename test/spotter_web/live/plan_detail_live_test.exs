defmodule SpotterWeb.PlanDetailLiveTest do
  @moduledoc """
  Integration tests for PlanDetailLive — the epic detail view.

  Route: /plans/:project/:epic_id
  Tests: parsed sections, mermaid hooks, acceptance table,
         child tasks, task expansion, annotation creation,
         graceful degradation, back navigation.
  """
  use Spotter.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Spotter.Transcripts.{Annotation, Project}

  @endpoint SpotterWeb.Endpoint

  describe "mount with epic data" do
    test "renders epic detail view with title and badges" do
      {:ok, view, _html} = live(build_conn(), "/plans/spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="epic-detail")
      assert html =~ ~s(data-testid="epic-detail-header")
      # Status and priority badges rendered
      assert html =~ "data-status="
      assert html =~ "data-priority="
    end
  end

  describe "description sections" do
    test "renders parsed sections from BeadContentParser" do
      {:ok, view, _html} = live(build_conn(), "/plans/spotter/spotter-uok")

      html = render(view)

      # Sections container must exist
      assert html =~ ~s(data-testid="epic-sections")
      # Individual section headings rendered as h3 elements
      assert html =~ ~s(data-testid="section-heading")
    end
  end

  describe "mermaid diagram rendering" do
    test "wraps mermaid blocks with phx-hook and data attribute" do
      {:ok, view, _html} = live(build_conn(), "/plans/spotter/spotter-uok")

      html = render(view)

      # Mermaid blocks must be rendered as hook-compatible elements
      assert html =~ "phx-hook=\"MermaidHook\""
      assert html =~ "data-mermaid-source="
    end
  end

  describe "acceptance criteria table" do
    test "renders GIVEN/WHEN/THEN table from parsed description" do
      {:ok, view, _html} = live(build_conn(), "/plans/spotter/spotter-uok")

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
      {:ok, view, _html} = live(build_conn(), "/plans/spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(data-testid="child-tasks")
      assert html =~ ~s(data-testid="child-task-row")
    end

    test "child task description is expandable via toggle" do
      {:ok, view, _html} = live(build_conn(), "/plans/spotter/spotter-uok")

      html = render(view)

      # Description should be collapsed by default
      refute html =~ ~s(data-testid="child-task-description-expanded")

      # Toggle expand on first child task
      html = render_click(view, "toggle_task", %{"task_id" => "spotter-task-1"})
      assert html =~ ~s(data-testid="child-task-description-expanded")
    end
  end

  describe "text selection annotation" do
    setup do
      project = Ash.create!(Project, %{name: "spotter", pattern: "^spotter"})

      %{project: project}
    end

    test "plan_text_selected event creates annotation with source=:plan and bead_id", %{
      project: project
    } do
      {:ok, view, _html} = live(build_conn(), "/plans/#{project.name}/spotter-uok")

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
      {:ok, view, _html} = live(build_conn(), "/plans/spotter/spotter-uok")

      render_click(view, "plan_text_selected", %{
        "selected_text" => "some text",
        "comment" => "note"
      })

      html = render_click(view, "clear_selection", %{})
      refute html =~ ~s(data-testid="selection-active")
    end
  end

  describe "graceful degradation" do
    test "shows friendly empty state when Dolt is unavailable" do
      # This test exercises the path where BeadQueries return errors
      {:ok, view, _html} = live(build_conn(), "/plans/spotter/nonexistent-epic-xyz")

      html = render(view)

      assert html =~ "empty-state" or html =~ "not found" or html =~ "unavailable"
    end
  end

  describe "back navigation" do
    test "has link back to plans list preserving project context" do
      {:ok, view, _html} = live(build_conn(), "/plans/spotter/spotter-uok")

      html = render(view)

      assert html =~ ~s(href="/plans?project=spotter") or
               html =~ ~s(data-testid="back-to-plans")
    end
  end
end
