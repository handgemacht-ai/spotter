defmodule SpotterWeb.ProjectContextTest do
  use Spotter.DataCase, async: false

  alias Spotter.Transcripts.Project

  defp mount(params) do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    SpotterWeb.ProjectContext.on_mount(:default, params, %{}, socket)
  end

  describe "on_mount/4 with valid project param" do
    test "assigns matching project_id when ?project= matches an existing project" do
      # GIVEN two projects exist
      project_a = Ash.create!(Project, %{name: "alpha", pattern: "^alpha"})
      _project_b = Ash.create!(Project, %{name: "beta", pattern: "^beta"})

      # WHEN on_mount is called with project param matching project_a
      {:cont, socket} = mount(%{"project" => project_a.id})

      # THEN current_project_id is set to project_a and both projects are loaded
      assert socket.assigns.current_project_id == project_a.id
      assert length(socket.assigns.projects) == 2
    end
  end

  describe "on_mount/4 with legacy project_id param" do
    test "falls back to ?project_id= when ?project= is absent" do
      # GIVEN two projects exist
      _project_a = Ash.create!(Project, %{name: "alpha", pattern: "^alpha"})
      project_b = Ash.create!(Project, %{name: "beta", pattern: "^beta"})

      # WHEN on_mount is called with project_id param pointing to the second project
      {:cont, socket} = mount(%{"project_id" => project_b.id})

      # THEN current_project_id is set from the legacy param (not defaulting to first)
      assert socket.assigns.current_project_id == project_b.id
    end
  end

  describe "on_mount/4 with no project param" do
    test "auto-selects first project when no param is provided" do
      # GIVEN two projects exist (alpha sorts first)
      project_a = Ash.create!(Project, %{name: "alpha", pattern: "^alpha"})
      _project_b = Ash.create!(Project, %{name: "beta", pattern: "^beta"})

      # WHEN on_mount is called with empty params
      {:cont, socket} = mount(%{})

      # THEN defaults to first project alphabetically
      assert socket.assigns.current_project_id == project_a.id
      assert is_list(socket.assigns.projects)
    end
  end

  describe "on_mount/4 with invalid project param" do
    test "falls back to first project when ?project= does not match any project" do
      # GIVEN two projects exist
      project_a = Ash.create!(Project, %{name: "alpha", pattern: "^alpha"})
      _project_b = Ash.create!(Project, %{name: "beta", pattern: "^beta"})

      # WHEN on_mount is called with a non-existent project id
      {:cont, socket} = mount(%{"project" => "nonexistent-id"})

      # THEN falls back to first project alphabetically
      assert socket.assigns.current_project_id == project_a.id
    end
  end

  describe "on_mount/4 with empty projects" do
    test "assigns nil when no projects exist" do
      # GIVEN no projects exist
      # WHEN on_mount is called
      {:cont, socket} = mount(%{})

      # THEN assigns nil and empty list
      assert socket.assigns.current_project_id == nil
      assert socket.assigns.projects == []
    end
  end

  describe "on_mount/4 always continues" do
    test "returns {:cont, socket} and never halts" do
      # GIVEN no projects exist
      # WHEN on_mount is called
      result = mount(%{})

      # THEN returns :cont tuple (never :halt)
      assert {:cont, %Phoenix.LiveView.Socket{}} = result
    end
  end
end
