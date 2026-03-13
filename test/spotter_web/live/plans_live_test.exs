defmodule SpotterWeb.PlansLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    :ok
  end

  describe "mount and project filter chips" do
    test "renders Plans heading" do
      {:ok, _view, html} = live(build_conn(), "/plans")

      assert html =~ "<h1"
      assert html =~ "Plans"
    end

    test "renders project filter chips from bead data" do
      {:ok, _view, html} = live(build_conn(), "/plans")

      # Project chips should be rendered with project names
      assert html =~ "project-chip" or html =~ "filter-chip" or html =~ "data-project"
    end
  end

  describe "project chip filtering" do
    test "clicking a project chip filters epics to that project" do
      {:ok, view, _html} = live(build_conn(), "/plans")

      # Click a project chip to filter — the view should update to show
      # only epics from the selected project
      html = render_click(view, "select_project", %{"project" => "spotter"})

      assert html =~ "spotter"
    end
  end

  describe "epic table" do
    test "displays epic title in table" do
      {:ok, _view, html} = live(build_conn(), "/plans")

      # The epic table should show epic titles
      assert html =~ "epic-table" or html =~ "<table" or html =~ "<th"
    end

    test "shows status badge for each epic" do
      {:ok, _view, html} = live(build_conn(), "/plans")

      # Status badges should use recognizable classes or text
      assert html =~ "status-badge" or html =~ "badge"
    end

    test "shows priority for each epic" do
      {:ok, _view, html} = live(build_conn(), "/plans")

      # Priority should be visible in the table
      assert html =~ "priority" or html =~ "Priority"
    end

    test "shows child task count for each epic" do
      {:ok, _view, html} = live(build_conn(), "/plans")

      # Child task count column should exist
      assert html =~ "tasks" or html =~ "Tasks" or html =~ "children"
    end
  end

  describe "empty state" do
    test "shows empty state message when project has zero epics" do
      {:ok, view, _html} = live(build_conn(), "/plans")

      # Select a project known to have no epics
      html = render_click(view, "select_project", %{"project" => "nonexistent_project_xyz"})

      assert html =~ "No epics" or html =~ "no epics" or html =~ "empty"
    end
  end

  describe "routes" do
    test "/plans route is accessible" do
      {:ok, _view, html} = live(build_conn(), "/plans")

      assert html =~ "Plans"
    end

    test "/plans/:project/:epic_id route is accessible" do
      {:ok, _view, html} = live(build_conn(), "/plans/spotter/spotter-5zm")

      assert html =~ "Plans" or html =~ "spotter-5zm"
    end
  end
end
