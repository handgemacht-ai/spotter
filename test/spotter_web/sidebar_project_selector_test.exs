defmodule SpotterWeb.SidebarProjectSelectorTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.Project

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "sidebar project selector renders" do
    test "shows project selector section with current project name" do
      # GIVEN two projects exist
      project_a = Ash.create!(Project, %{name: "alpha", pattern: "^alpha"})
      _project_b = Ash.create!(Project, %{name: "beta", pattern: "^beta"})

      # WHEN we load the dashboard with a project param
      {:ok, _view, html} = live(build_conn(), "/?project=#{project_a.id}")

      # THEN the sidebar contains the project selector section
      assert html =~ "sidebar-project"
      assert html =~ "PROJECT"
      assert html =~ "project-selector"
      assert html =~ "alpha"
    end
  end

  describe "nav links include project param" do
    test "sidebar nav links carry ?project= query param" do
      # GIVEN a project exists
      project = Ash.create!(Project, %{name: "alpha", pattern: "^alpha"})

      # WHEN we load any page
      {:ok, _view, html} = live(build_conn(), "/?project=#{project.id}")

      # THEN each nav link includes ?project=<id>
      assert html =~ ~s(href="/sessions?project=#{project.id}")
      assert html =~ ~s(href="/reviews?project=#{project.id}")
      assert html =~ ~s(href="/history?project=#{project.id}")
      assert html =~ ~s(href="/retros?project=#{project.id}")
      assert html =~ ~s(href="/file-metrics?project=#{project.id}")
    end
  end

  describe "dropdown lists all projects" do
    test "project selector dropdown contains all project names" do
      # GIVEN three projects exist
      project_a = Ash.create!(Project, %{name: "alpha", pattern: "^alpha"})
      _project_b = Ash.create!(Project, %{name: "beta", pattern: "^beta"})
      _project_c = Ash.create!(Project, %{name: "gamma", pattern: "^gamma"})

      # WHEN we load the page
      {:ok, _view, html} = live(build_conn(), "/?project=#{project_a.id}")

      # THEN the dropdown contains all project names as options
      assert html =~ ~s(role="listbox")
      assert html =~ ~s(role="option")
      assert html =~ "alpha"
      assert html =~ "beta"
      assert html =~ "gamma"
    end
  end

  describe "no projects edge case" do
    test "shows 'No projects' when no projects exist" do
      # GIVEN no projects exist
      # WHEN we load the page
      {:ok, _view, html} = live(build_conn(), "/")

      # THEN the sidebar shows a no-projects indicator
      assert html =~ "No projects"
    end
  end
end
