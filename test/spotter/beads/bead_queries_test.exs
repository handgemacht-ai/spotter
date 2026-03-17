defmodule Spotter.Beads.BeadQueriesTest do
  use ExUnit.Case, async: false

  import Spotter.Test.OtelHelpers

  @moduletag :live_dolt
  @moduletag timeout: 30_000

  alias Spotter.Beads.Client
  @queries_module Spotter.Beads.BeadQueries
  @epic_module Spotter.Beads.BeadStructs.Epic
  @task_module Spotter.Beads.BeadStructs.Task

  setup do
    setup_otel_test(%{})
    :ok
  end

  describe "project_summaries/0" do
    test "returns project names with epic counts" do
      assert {:ok, summaries} = @queries_module.project_summaries()
      assert is_list(summaries)

      Enum.each(summaries, fn summary ->
        assert is_binary(summary.project)
        assert is_integer(summary.epic_count)
        assert summary.epic_count >= 0
      end)
    end

    test "includes at least the spotter project" do
      assert {:ok, summaries} = @queries_module.project_summaries()
      projects = Enum.map(summaries, & &1.project)
      assert "spotter" in projects
    end
  end

  describe "list_epics/1" do
    test "returns epics as Epic structs for a project" do
      assert {:ok, epics} = @queries_module.list_epics("spotter")
      assert is_list(epics)

      Enum.each(epics, fn epic ->
        assert epic.__struct__ == @epic_module
        assert is_binary(epic.id)
        assert is_binary(epic.title)
        assert epic.issue_type == "epic"
      end)
    end

    test "filters epics by open status" do
      assert {:ok, epics} = @queries_module.list_epics("spotter", :open)

      Enum.each(epics, fn epic ->
        assert epic.__struct__ == @epic_module
        assert epic.status == "open"
      end)
    end

    test "filters epics by closed status" do
      assert {:ok, epics} = @queries_module.list_epics("spotter", :closed)

      Enum.each(epics, fn epic ->
        assert epic.__struct__ == @epic_module
        assert epic.status == "closed"
      end)
    end

    test "returns error for nonexistent project" do
      assert {:error, reason} = @queries_module.list_epics("nonexistent_project_xyz")
      assert reason in [:connection_refused, :unknown_project]
    end
  end

  describe "get_epic/2" do
    test "returns full epic data as Epic struct" do
      {:ok, epics} = @queries_module.list_epics("spotter")

      case epics do
        [epic | _] ->
          assert {:ok, fetched} = @queries_module.get_epic("spotter", epic.id)
          assert fetched.__struct__ == @epic_module
          assert fetched.id == epic.id
          assert is_binary(fetched.title)
          assert fetched.issue_type == "epic"

        [] ->
          assert {:error, :not_found} = @queries_module.get_epic("spotter", "nonexistent-999")
      end
    end

    test "returns error for nonexistent epic ID" do
      assert {:error, :not_found} = @queries_module.get_epic("spotter", "nonexistent-999")
    end
  end

  describe "list_children/2" do
    test "returns child tasks as Task structs" do
      {:ok, epics} = @queries_module.list_epics("spotter")

      case epics do
        [epic | _] ->
          assert {:ok, children} = @queries_module.list_children("spotter", epic.id)
          assert is_list(children)

          Enum.each(children, fn child ->
            assert child.__struct__ == @task_module
            assert is_binary(child.id)
            assert is_binary(child.title)
          end)

        [] ->
          assert {:ok, []} = @queries_module.list_children("spotter", "nonexistent-999")
      end
    end

    test "returns empty list for epic with no children" do
      assert {:ok, children} = @queries_module.list_children("spotter", "nonexistent-999")
      assert children == []
    end

    test "finds children linked via parent-child deps" do
      # Query raw to find an epic with parent-child children
      {:ok, result} =
        Client.query("spotter", """
        SELECT d.depends_on_id
        FROM dependencies d
        JOIN issues i ON i.id = d.depends_on_id AND i.issue_type = 'epic'
        WHERE d.type = 'parent-child'
        GROUP BY d.depends_on_id
        HAVING COUNT(*) > 0
        LIMIT 1
        """)

      case result.rows do
        [[epic_id]] ->
          assert {:ok, children} = @queries_module.list_children("spotter", epic_id)

          assert children != [],
                 "Epic #{epic_id} has parent-child deps but list_children returned []"

          Enum.each(children, fn child ->
            assert child.__struct__ == @task_module
          end)

        [] ->
          :ok
      end
    end
  end
end
