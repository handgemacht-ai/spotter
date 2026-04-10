defmodule Spotter.Beads.DoltConfigTest do
  use ExUnit.Case, async: true

  alias Spotter.Beads.DoltConfig

  describe "database_name/1" do
    test "returns project name when no mapping configured" do
      original = Application.get_env(:spotter, DoltConfig)
      Application.delete_env(:spotter, DoltConfig)

      on_exit(fn ->
        if original, do: Application.put_env(:spotter, DoltConfig, original)
      end)

      assert DoltConfig.database_name("spotter") == "spotter"
      assert DoltConfig.database_name("levio") == "levio"
    end

    test "uses database_mapping when configured" do
      original = Application.get_env(:spotter, DoltConfig)

      Application.put_env(:spotter, DoltConfig, database_mapping: %{"spotter" => "beads_spotter"})

      on_exit(fn ->
        if original do
          Application.put_env(:spotter, DoltConfig, original)
        else
          Application.delete_env(:spotter, DoltConfig)
        end
      end)

      assert DoltConfig.database_name("spotter") == "beads_spotter"
      assert DoltConfig.database_name("levio") == "levio"
    end
  end
end
