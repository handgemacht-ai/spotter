defmodule Spotter.Beads.BeadQueriesDependenciesTest do
  use ExUnit.Case, async: false

  import Spotter.Test.OtelHelpers

  @moduletag timeout: 30_000

  @queries_module Spotter.Beads.BeadQueries
  @dependency_module Spotter.Beads.BeadStructs.Dependency

  setup do
    setup_otel_test(%{})
    :ok
  end

  describe "list_dependencies/2" do
    test "returns Dependency structs for an issue with dependencies" do
      assert {:ok, deps} = @queries_module.list_dependencies("spotter", "spotter-epic-1")
      assert is_list(deps)

      Enum.each(deps, fn dep ->
        assert dep.__struct__ == @dependency_module
        assert is_binary(dep.depends_on_id)
        assert is_binary(dep.type)
      end)
    end

    test "returns empty list for issue with no dependencies" do
      assert {:ok, deps} = @queries_module.list_dependencies("spotter", "nonexistent-999")
      assert deps == []
    end

    test "returns error for nonexistent project" do
      assert {:error, :not_configured} =
               @queries_module.list_dependencies("nonexistent_project_xyz", "any")
    end
  end
end
