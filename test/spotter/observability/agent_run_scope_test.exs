defmodule Spotter.Observability.AgentRunScopeTest do
  use ExUnit.Case, async: false

  alias Spotter.Observability.AgentRunScope

  @table AgentRunScope

  setup do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  describe "put/get/delete lifecycle" do
    test "stores and retrieves scope by registry pid" do
      pid = spawn(fn -> Process.sleep(:infinity) end)

      scope = %{
        project_id: "019c5952-42f5-7e7e-a8b7-e10e1619db24",
        commit_hash: String.duplicate("a", 40),
        git_cwd: "/tmp/repo",
        agent_kind: "product_spec"
      }

      assert :ok = AgentRunScope.put(pid, scope)
      assert {:ok, ^scope} = AgentRunScope.get(pid)

      Process.exit(pid, :kill)
    end

    test "delete removes scope entry" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      scope = %{project_id: "abc", agent_kind: "hotspot"}

      AgentRunScope.put(pid, scope)
      assert {:ok, _} = AgentRunScope.get(pid)

      assert :ok = AgentRunScope.delete(pid)
      assert :error = AgentRunScope.get(pid)

      Process.exit(pid, :kill)
    end

    test "get returns :error for unknown pid" do
      pid = spawn(fn -> :ok end)
      Process.sleep(10)
      assert :error = AgentRunScope.get(pid)
    end

    test "delete on unknown pid is a no-op" do
      pid = spawn(fn -> :ok end)
      Process.sleep(10)
      assert :ok = AgentRunScope.delete(pid)
    end
  end

  describe "resolve_for_current_process/0" do
    test "returns scope when exactly one entry exists" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      scope = %{project_id: "proj-1", commit_hash: "abc123", agent_kind: "hotspot"}

      AgentRunScope.put(pid, scope)
      assert {:ok, ^scope} = AgentRunScope.resolve_for_current_process()

      AgentRunScope.delete(pid)
      Process.exit(pid, :kill)
    end

    test "returns error when table is empty" do
      assert {:error, :no_scope} = AgentRunScope.resolve_for_current_process()
    end

    test "returns scope from ancestor pid if present in ETS" do
      # Simulate a process whose $ancestors list includes a pid stored in ETS
      registry_pid = spawn(fn -> Process.sleep(:infinity) end)
      scope = %{project_id: "proj-ancestor", agent_kind: "product_spec"}

      AgentRunScope.put(registry_pid, scope)

      # Spawn a task that has registry_pid in its $ancestors (simulated)
      task =
        Task.async(fn ->
          Process.put(:"$ancestors", [registry_pid])
          AgentRunScope.resolve_for_current_process()
        end)

      assert {:ok, ^scope} = Task.await(task)

      AgentRunScope.delete(registry_pid)
      Process.exit(registry_pid, :kill)
    end
  end

  describe "deterministic and fail-safe behavior" do
    test "put validates registry_pid is a pid" do
      assert_raise FunctionClauseError, fn ->
        AgentRunScope.put("not_a_pid", %{})
      end
    end

    test "put validates scope is a map" do
      pid = spawn(fn -> Process.sleep(:infinity) end)

      assert_raise FunctionClauseError, fn ->
        AgentRunScope.put(pid, "not_a_map")
      end

      Process.exit(pid, :kill)
    end

    test "concurrent put/delete does not raise" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            pid = spawn(fn -> Process.sleep(:infinity) end)
            scope = %{project_id: "proj-#{i}", agent_kind: "test"}
            AgentRunScope.put(pid, scope)
            AgentRunScope.get(pid)
            AgentRunScope.delete(pid)
            Process.exit(pid, :kill)
            :ok
          end)
        end

      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end
end
