defmodule Spotter.Beads.ClientTest do
  use ExUnit.Case, async: false

  import Spotter.Test.OtelHelpers

  @moduletag timeout: 30_000

  alias Spotter.Beads.Client

  setup do
    setup_otel_test(%{})
    :ok
  end

  describe "list_epics/2" do
    test "returns {:ok, list} of epic issues and emits span" do
      assert {:ok, epics} = Client.list_epics("spotter", :all)
      assert is_list(epics)
      assert epics != []

      assert_span_attributes("spotter.beads.client.list_epics", %{
        "spotter.beads.database" => "spotter",
        "spotter.beads.query_name" => "list_epics"
      })
    end

    test "filters by open status" do
      assert {:ok, epics} = Client.list_epics("spotter", :open)

      Enum.each(epics, fn epic ->
        assert epic.status == "open"
      end)
    end

    test "filters by closed status" do
      assert {:ok, epics} = Client.list_epics("spotter", :closed)

      Enum.each(epics, fn epic ->
        assert epic.status == "closed"
      end)
    end

    test "returns epics with expected fields" do
      assert {:ok, [epic | _]} = Client.list_epics("spotter", :all)

      assert Map.has_key?(epic, :id)
      assert Map.has_key?(epic, :title)
      assert Map.has_key?(epic, :status)
      assert Map.has_key?(epic, :priority)
      assert Map.has_key?(epic, :issue_type)
      assert epic.issue_type == "epic"
      assert Map.has_key?(epic, :task_count)
    end
  end

  describe "get_issue/2" do
    test "returns {:ok, issue} for existing bead ID" do
      assert {:ok, issue} = Client.get_issue("spotter", "spotter-epic-1")
      assert issue.id == "spotter-epic-1"
      assert is_binary(issue.title)

      assert_span_attributes("spotter.beads.client.get_issue", %{
        "spotter.beads.database" => "spotter",
        "spotter.beads.query_name" => "get_issue"
      })
    end

    test "returns {:error, :not_found} for nonexistent bead ID" do
      assert {:error, :not_found} = Client.get_issue("spotter", "nonexistent-999")

      assert_span_recorded("spotter.beads.client.get_issue")
    end
  end

  describe "get_children/2" do
    test "returns child issues for a parent epic" do
      assert {:ok, children} = Client.get_children("spotter", "spotter-epic-1")
      assert length(children) == 3

      child_ids = Enum.map(children, & &1.id)
      assert "spotter-task-1" in child_ids
      assert "spotter-task-2" in child_ids
      assert "spotter-task-3" in child_ids

      assert_span_attributes("spotter.beads.client.get_children", %{
        "spotter.beads.database" => "spotter",
        "spotter.beads.query_name" => "get_children"
      })
    end

    test "returns {:ok, []} for bead with no children" do
      assert {:ok, children} = Client.get_children("spotter", "nonexistent-999")
      assert children == []
    end
  end

  describe "epic_counts_by_project/0" do
    test "returns a map of project_name => count and emits span" do
      assert {:ok, counts} = Client.epic_counts_by_project()
      assert is_map(counts)

      Enum.each(counts, fn {project, count} ->
        assert is_binary(project)
        assert is_integer(count)
        assert count >= 0
      end)

      assert_span_attributes("spotter.beads.client.epic_counts_by_project", %{
        "spotter.beads.query_name" => "epic_counts_by_project"
      })
    end
  end

  describe "get_dependencies/2" do
    test "returns dependencies for an issue" do
      assert {:ok, deps} = Client.get_dependencies("spotter", "spotter-epic-1")
      assert length(deps) == 1

      [dep] = deps
      assert dep.depends_on_id == "spotter-epic-2"
      assert dep.type == "discovered-from"

      assert_span_attributes("spotter.beads.client.get_dependencies", %{
        "spotter.beads.database" => "spotter",
        "spotter.beads.query_name" => "get_dependencies"
      })
    end

    test "returns empty list for issue with no dependencies" do
      assert {:ok, []} = Client.get_dependencies("spotter", "spotter-orphan-1")
    end
  end

  describe "list_orphan_issues/2" do
    test "returns non-epic issues without parent dependencies" do
      assert {:ok, orphans} = Client.list_orphan_issues("spotter", :all)
      orphan_ids = Enum.map(orphans, & &1.id)

      assert "spotter-orphan-1" in orphan_ids
      refute "spotter-task-1" in orphan_ids
      refute "spotter-epic-1" in orphan_ids
    end
  end

  describe "search_beads/2" do
    test "searches by query string" do
      assert {:ok, results} = Client.search_beads("spotter", query: "Plans")
      assert Enum.any?(results, &(&1.id == "spotter-epic-1"))
    end

    test "filters by status" do
      assert {:ok, results} = Client.search_beads("spotter", status: :closed)

      Enum.each(results, fn r ->
        assert r.status == "closed"
      end)
    end
  end

  describe "get_sibling_graph/2" do
    test "returns graph for a task with siblings" do
      assert {:ok, graph} = Client.get_sibling_graph("spotter", "spotter-task-1")
      assert is_map(graph)
      assert is_list(graph.nodes)
      assert is_list(graph.edges)
      assert length(graph.nodes) == 3
    end

    test "returns nil when fewer than 2 siblings" do
      assert {:ok, nil} = Client.get_sibling_graph("spotter", "spotter-orphan-1")
    end
  end

  describe "error handling" do
    test "returns {:error, :not_configured} for unknown project" do
      assert {:error, :not_configured} = Client.list_epics("nonexistent_project", :all)
    end
  end
end
