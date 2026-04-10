defmodule Spotter.Beads.ClientEmbeddedTest do
  use ExUnit.Case, async: true

  alias Spotter.Beads.Client
  alias Spotter.Beads.DoltStore

  @project "test_project"

  setup do
    case DoltStore.get_state(@project) do
      {:ok, _} ->
        :ok

      {:error, :not_started} ->
        start_supervised!(DoltStore.child_spec(@project))
        poll_until_loaded()
        :ok
    end
  end

  describe "list_epics/2 (embedded)" do
    test "returns all epics" do
      assert {:ok, epics} = Client.list_epics(@project, :all)
      ids = Enum.map(epics, & &1.id)
      assert "test-epic-1" in ids
      assert "test-epic-2" in ids
    end

    test "filters open epics" do
      assert {:ok, epics} = Client.list_epics(@project, :open)
      assert Enum.all?(epics, &(&1.status == "open"))
      assert length(epics) == 1
    end

    test "filters closed epics" do
      assert {:ok, epics} = Client.list_epics(@project, :closed)
      assert Enum.all?(epics, &(&1.status == "closed"))
      assert length(epics) == 1
    end
  end

  describe "get_issue/2 (embedded)" do
    test "returns existing issue" do
      assert {:ok, issue} = Client.get_issue(@project, "test-epic-1")
      assert issue.title == "Epic One"
      assert issue.issue_type == "epic"
    end

    test "returns not_found for missing issue" do
      assert {:error, :not_found} = Client.get_issue(@project, "nonexistent")
    end
  end

  describe "get_children/2 (embedded)" do
    test "returns children of an epic" do
      assert {:ok, children} = Client.get_children(@project, "test-epic-1")
      ids = Enum.map(children, & &1.id)
      assert "test-task-1" in ids
      assert "test-task-2" in ids
      assert "test-task-3" in ids
    end

    test "returns empty list for issue with no children" do
      assert {:ok, []} = Client.get_children(@project, "test-orphan-1")
    end
  end

  describe "get_dependencies/2 (embedded)" do
    test "returns dependencies with target info" do
      assert {:ok, deps} = Client.get_dependencies(@project, "test-task-2")
      assert length(deps) == 2

      parent_dep = Enum.find(deps, &(&1.type == "parent-child"))
      assert parent_dep.depends_on_id == "test-epic-1"
      assert parent_dep.depends_on_title == "Epic One"

      blocks_dep = Enum.find(deps, &(&1.type == "blocks"))
      assert blocks_dep.depends_on_id == "test-task-1"
    end

    test "returns empty for issue with no dependencies" do
      assert {:ok, []} = Client.get_dependencies(@project, "test-epic-1")
    end
  end

  describe "list_orphan_issues/2 (embedded)" do
    test "returns non-epic issues without parent deps" do
      assert {:ok, orphans} = Client.list_orphan_issues(@project, :all)
      ids = Enum.map(orphans, & &1.id)
      assert "test-orphan-1" in ids
      refute "test-task-1" in ids
      refute "test-epic-1" in ids
    end
  end

  describe "search_beads/2 (embedded)" do
    test "returns epics and orphans" do
      assert {:ok, results} = Client.search_beads(@project, status: :all)
      ids = Enum.map(results, & &1.id)
      assert "test-epic-1" in ids
      assert "test-orphan-1" in ids
    end

    test "text search filters by title" do
      assert {:ok, results} = Client.search_beads(@project, query: "Orphan", status: :all)
      assert length(results) == 1
      assert hd(results).id == "test-orphan-1"
    end

    test "epics have task_count" do
      assert {:ok, results} = Client.search_beads(@project, status: :all, types: [:epic])
      epic = Enum.find(results, &(&1.id == "test-epic-1"))
      assert epic.task_count == 3
    end
  end

  describe "get_sibling_graph/2 (embedded)" do
    test "returns graph for task with siblings" do
      assert {:ok, graph} = Client.get_sibling_graph(@project, "test-task-1")
      assert is_map(graph)
      assert length(graph.nodes) == 3

      edge = Enum.find(graph.edges, &(&1.type == "blocks"))
      assert edge.from == "test-task-2"
      assert edge.to == "test-task-1"
    end

    test "returns nil for issue with fewer than 2 siblings" do
      assert {:ok, nil} = Client.get_sibling_graph(@project, "test-orphan-1")
    end
  end

  defp poll_until_loaded(attempts \\ 20) do
    case DoltStore.get_state(@project) do
      {:ok, _} ->
        :ok

      {:error, _} when attempts > 0 ->
        Process.sleep(50)
        poll_until_loaded(attempts - 1)

      {:error, reason} ->
        flunk("DoltStore did not load: #{inspect(reason)}")
    end
  end
end
