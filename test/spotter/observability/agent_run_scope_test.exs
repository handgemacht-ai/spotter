defmodule Spotter.Observability.AgentRunScopeTest do
  use ExUnit.Case, async: false

  alias Spotter.Observability.AgentRunScope

  @table AgentRunScope

  setup do
    AgentRunScope.ensure_table_exists()

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
    test "returns error when table has entries but current process has no ancestor link" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      scope = %{project_id: "proj-1", commit_hash: "abc123", agent_kind: "hotspot"}

      AgentRunScope.put(pid, scope)
      assert {:error, :no_scope} = AgentRunScope.resolve_for_current_process()

      AgentRunScope.delete(pid)
      Process.exit(pid, :kill)
    end

    test "returns error when table is empty" do
      assert {:error, :no_scope} = AgentRunScope.resolve_for_current_process()
    end

    test "does not arbitrarily select from multiple ETS entries" do
      pids =
        for i <- 1..3 do
          pid = spawn(fn -> Process.sleep(:infinity) end)
          AgentRunScope.put(pid, %{project_id: "proj-#{i}", agent_kind: "test"})
          pid
        end

      assert {:error, :no_scope} = AgentRunScope.resolve_for_current_process()

      for pid <- pids do
        AgentRunScope.delete(pid)
        Process.exit(pid, :kill)
      end
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

    test "returns scope from $callers lineage for Task.Supervisor child workers" do
      sup_name = :"scope-lineage-sup-#{System.unique_integer([:positive])}"
      sup = start_supervised!({Task.Supervisor, name: sup_name})

      registry_pid =
        spawn(fn ->
          receive do
            {:run, parent} ->
              {:ok, _task_pid} =
                Task.Supervisor.start_child(sup, fn ->
                  send(parent, {
                    :resolved_from_lineage,
                    AgentRunScope.resolve_for_current_process(),
                    Process.get(:"$ancestors", []),
                    Process.get(:"$callers", [])
                  })
                end)

              Process.sleep(250)
          end
        end)

      scope = %{project_id: "proj-caller", agent_kind: "commit_test"}
      AgentRunScope.put(registry_pid, scope)
      send(registry_pid, {:run, self()})

      assert_receive {:resolved_from_lineage, {:ok, ^scope}, ancestors, callers}, 1_000
      refute registry_pid in ancestors
      assert registry_pid in callers

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
      # Ensure table exists before spawning concurrent tasks.
      AgentRunScope.ensure_table_exists()

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

    test "table is not owned by short-lived caller processes" do
      owner_before = :ets.info(@table, :owner)
      parent = self()

      caller =
        spawn(fn ->
          AgentRunScope.ensure_table_exists()
          send(parent, {:caller_done, self(), :ets.info(@table, :owner)})
        end)

      assert_receive {:caller_done, ^caller, owner_during}
      assert owner_during == owner_before

      Process.exit(caller, :kill)
      Process.sleep(25)

      assert :ets.whereis(@table) != :undefined
      assert :ets.info(@table, :owner) == owner_before
    end
  end
end
