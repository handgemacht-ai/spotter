defmodule SpotterWeb.ProjectHelpersTest do
  use ExUnit.Case, async: true

  alias SpotterWeb.ProjectHelpers

  describe "parse_project_id/1" do
    test "returns nil for \"all\"" do
      assert ProjectHelpers.parse_project_id("all") == nil
    end

    test "returns nil for nil" do
      assert ProjectHelpers.parse_project_id(nil) == nil
    end

    test "returns nil for empty string" do
      assert ProjectHelpers.parse_project_id("") == nil
    end

    test "returns the id for a valid string" do
      assert ProjectHelpers.parse_project_id("proj_123") == "proj_123"
    end
  end

  describe "first_project_id/1" do
    test "returns nil for empty list" do
      assert ProjectHelpers.first_project_id([]) == nil
    end

    test "extracts id from %{id: ...} structs" do
      projects = [%{id: "proj_1", name: "A"}, %{id: "proj_2", name: "B"}]
      assert ProjectHelpers.first_project_id(projects) == "proj_1"
    end

    test "extracts project_id from %{project_id: ...} structs" do
      counts = [%{project_id: "proj_x", count: 5}, %{project_id: "proj_y", count: 3}]
      assert ProjectHelpers.first_project_id(counts) == "proj_x"
    end
  end

  describe "project_exists?/2" do
    test "returns true when project_id matches %{id: ...} struct" do
      projects = [%{id: "proj_1"}, %{id: "proj_2"}]
      assert ProjectHelpers.project_exists?(projects, "proj_2")
    end

    test "returns false when project_id not found in %{id: ...} structs" do
      projects = [%{id: "proj_1"}, %{id: "proj_2"}]
      refute ProjectHelpers.project_exists?(projects, "proj_missing")
    end

    test "returns true when project_id matches %{project_id: ...} struct" do
      counts = [%{project_id: "proj_a"}, %{project_id: "proj_b"}]
      assert ProjectHelpers.project_exists?(counts, "proj_b")
    end

    test "returns false when project_id not found in %{project_id: ...} structs" do
      counts = [%{project_id: "proj_a"}, %{project_id: "proj_b"}]
      refute ProjectHelpers.project_exists?(counts, "proj_missing")
    end

    test "returns false for empty list" do
      refute ProjectHelpers.project_exists?([], "proj_1")
    end
  end

  describe "normalize_project_id/2" do
    test "returns first project id when project_id is nil" do
      projects = [%{id: "proj_1"}, %{id: "proj_2"}]
      assert ProjectHelpers.normalize_project_id(projects, nil) == "proj_1"
    end

    test "returns project_id when it exists in the list" do
      projects = [%{id: "proj_1"}, %{id: "proj_2"}]
      assert ProjectHelpers.normalize_project_id(projects, "proj_2") == "proj_2"
    end

    test "falls back to first project when project_id is invalid" do
      projects = [%{id: "proj_1"}, %{id: "proj_2"}]
      assert ProjectHelpers.normalize_project_id(projects, "proj_missing") == "proj_1"
    end

    test "returns nil when list is empty and project_id is nil" do
      assert ProjectHelpers.normalize_project_id([], nil) == nil
    end

    test "returns nil when list is empty and project_id is invalid" do
      assert ProjectHelpers.normalize_project_id([], "proj_missing") == nil
    end
  end
end
