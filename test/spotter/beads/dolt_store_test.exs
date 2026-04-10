defmodule Spotter.Beads.DoltStoreTest do
  use ExUnit.Case, async: true

  alias Spotter.Beads.DoltStore

  @fixture_project "test_project"

  setup do
    case DoltStore.get_state(@fixture_project) do
      {:ok, _} ->
        :ok

      {:error, :not_started} ->
        start_supervised!(DoltStore.child_spec(@fixture_project))
        poll_until_loaded()
        :ok
    end
  end

  describe "get_state/1" do
    test "returns loaded state with issues indexed by id" do
      assert {:ok, state} = DoltStore.get_state(@fixture_project)
      assert Map.has_key?(state.issues_by_id, "test-epic-1")
      assert Map.has_key?(state.issues_by_id, "test-task-1")
      assert Map.has_key?(state.issues_by_id, "test-orphan-1")
    end

    test "returns deps indexed by issue_id" do
      assert {:ok, state} = DoltStore.get_state(@fixture_project)
      assert Map.has_key?(state.deps_by_issue, "test-task-2")
      deps = state.deps_by_issue["test-task-2"]
      assert length(deps) == 2
    end

    test "returns child_ids as MapSet of parented issue IDs" do
      assert {:ok, state} = DoltStore.get_state(@fixture_project)
      assert MapSet.member?(state.child_ids, "test-task-1")
      assert MapSet.member?(state.child_ids, "test-task-2")
      assert MapSet.member?(state.child_ids, "test-task-3")
      refute MapSet.member?(state.child_ids, "test-orphan-1")
    end

    test "returns error for unconfigured project" do
      assert {:error, :not_started} = DoltStore.get_state("nonexistent")
    end
  end

  describe "project_config/1" do
    test "returns config for configured project" do
      config = DoltStore.project_config(@fixture_project)
      assert %{fixture_path: _} = config
    end

    test "returns nil for unconfigured project" do
      assert nil == DoltStore.project_config("nonexistent")
    end
  end

  describe "configured_projects/0" do
    test "includes test project" do
      assert @fixture_project in DoltStore.configured_projects()
    end
  end

  defp poll_until_loaded(attempts \\ 20) do
    case DoltStore.get_state(@fixture_project) do
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
