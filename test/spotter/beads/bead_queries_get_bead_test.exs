defmodule Spotter.Beads.BeadQueriesGetBeadTest do
  use ExUnit.Case, async: false

  import Spotter.Test.OtelHelpers

  @moduletag timeout: 30_000

  @queries_module Spotter.Beads.BeadQueries
  @epic_module Spotter.Beads.BeadStructs.Epic

  setup do
    setup_otel_test(%{})
    :ok
  end

  describe "get_bead/2" do
    test "delegates to get_epic/2 and returns same result" do
      assert {:ok, from_bead} = @queries_module.get_bead("spotter", "spotter-epic-1")
      assert {:ok, from_epic} = @queries_module.get_epic("spotter", "spotter-epic-1")
      assert from_bead == from_epic
      assert from_bead.__struct__ == @epic_module
    end

    test "returns not_found for nonexistent bead ID" do
      assert {:error, :not_found} = @queries_module.get_bead("spotter", "nonexistent-999")
    end
  end
end
