defmodule Spotter.Beads.BeadQueriesDependenciesTest do
  use ExUnit.Case, async: false

  import Spotter.Test.OtelHelpers

  @moduletag :live_dolt
  @moduletag timeout: 30_000

  @queries_module Spotter.Beads.BeadQueries
  @dependency_module Spotter.Beads.BeadStructs.Dependency

  setup do
    setup_otel_test(%{})
    :ok
  end

  describe "list_dependencies/2" do
    test "returns Dependency structs for an issue with dependencies" do
      {:ok, epics} = @queries_module.list_epics("spotter")

      case epics do
        [epic | _] ->
          assert {:ok, deps} = @queries_module.list_dependencies("spotter", epic.id)
          assert is_list(deps)

          Enum.each(deps, fn dep ->
            assert dep.__struct__ == @dependency_module
            assert is_binary(dep.depends_on_id)
            assert is_binary(dep.type)
          end)

        [] ->
          assert {:ok, []} = @queries_module.list_dependencies("spotter", "nonexistent-999")
      end
    end

    test "returns empty list for issue with no dependencies" do
      assert {:ok, deps} = @queries_module.list_dependencies("spotter", "nonexistent-999")
      assert deps == []
    end

    test "returns error for nonexistent project" do
      assert {:error, reason} =
               @queries_module.list_dependencies("nonexistent_project_xyz", "any")

      assert reason in [:connection_refused, :unknown_project]
    end
  end
end
