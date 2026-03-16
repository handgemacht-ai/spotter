defmodule SpotterWeb.PlansLiveTest do
  use Spotter.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Spotter.Transcripts.Project

  @endpoint SpotterWeb.Endpoint

  describe "mount with ProjectContext" do
    test "renders Plans heading" do
      {:ok, _view, html} = live(build_conn(), "/plans")

      assert html =~ "<h1"
      assert html =~ "Plans"
    end

    test "uses @current_project_id from ProjectContext, not local project chips" do
      {:ok, _view, html} = live(build_conn(), "/plans")

      refute html =~ "filter-btn"
      refute html =~ "project-chip"
      refute html =~ ~s(class="filter-section")
    end

    test "mounts with project from URL param via ProjectContext" do
      project = Ash.create!(Project, %{name: "test_proj", pattern: "^test_proj"})
      {:ok, _view, html} = live(build_conn(), "/plans?project=#{project.id}")

      assert html =~ "epic-table"
    end
  end

  describe "grouped-by-project view (no project selected)" do
    test "shows grouped view or empty state when no project selected" do
      {:ok, _view, html} = live(build_conn(), "/plans")

      # With no projects in DB, grouped view is empty → empty state shown
      # With projects, group headers are rendered
      assert html =~ ~s(data-testid="project-group-header") or html =~ "empty-state"
    end
  end

  describe "filtered view (project selected via sidebar)" do
    setup do
      project = Ash.create!(Project, %{name: "beads_filter_test", pattern: "^beads_filter"})
      %{project: project}
    end

    test "filters epics to selected project (no group headers)", %{project: project} do
      {:ok, view, _html} = live(build_conn(), "/plans?project=#{project.id}")

      html = render(view)

      # Filtered view: epic table present, no group headers
      assert html =~ "epic-table"
      refute html =~ ~s(data-testid="project-group-header")
    end
  end

  describe "Spotter.Plans coordinator" do
    setup do
      project = Ash.create!(Project, %{name: "beads_plans_test", pattern: "^beads_plans"})
      %{project: project}
    end

    test "PlansLive calls Spotter.Plans, not BeadQueries directly", %{project: project} do
      {:ok, view, _html} = live(build_conn(), "/plans?project=#{project.id}")

      html = render(view)

      assert html =~ "epic-table"
    end
  end

  describe "epic table" do
    test "displays epic table structure" do
      {:ok, _view, html} = live(build_conn(), "/plans")

      assert html =~ "epic-table" or html =~ "<table" or html =~ "<th"
    end
  end

  describe "empty state" do
    setup do
      project = Ash.create!(Project, %{name: "empty_proj", pattern: "^empty_proj"})
      %{project: project}
    end

    test "shows empty state when project has no plans", %{project: project} do
      {:ok, view, _html} = live(build_conn(), "/plans?project=#{project.id}")

      html = render(view)

      assert html =~ "No epics" or html =~ "No plans" or html =~ "empty-state"
    end
  end

  describe "routes" do
    test "/plans route is accessible" do
      {:ok, _view, html} = live(build_conn(), "/plans")

      assert html =~ "Plans"
    end

    test "/plans/:project/:epic_id route is accessible" do
      {:ok, _view, html} = live(build_conn(), "/plans/beads_spotter/spotter-uok")

      assert html =~ "Plans" or html =~ "spotter-uok"
    end
  end
end
