defmodule Spotter.Observability.AgentRunScope do
  @moduledoc """
  Shared ETS-based run scope for SDK tool-loop agents.

  Stores scope metadata keyed by the SDK MCP server registry pid,
  enabling tool execution tasks (spawned in separate processes via
  `ClaudeAgentSDK.TaskSupervisor`) to resolve their parent agent's
  scope without relying on process dictionary inheritance.

  Resolution is **fail-closed**: `resolve_for_current_process/0` only
  resolves scope via the calling process lineage (`$ancestors` and
  `$callers`). If no lineage pid has a matching ETS entry,
  `{:error, :no_scope}` is returned. There is no global table scan
  fallback, preventing cross-project scope leakage under concurrent
  agent runs.

  ## Why both `$ancestors` and `$callers`?

  `$ancestors` is set by OTP for linked/supervised processes and covers
  the normal `Task.async`/`Task.Supervisor.async` paths. However, the
  Claude Agent SDK dispatches `tools/call` requests through
  `TaskSupervisor` tasks that may not share `$ancestors` with the
  runner process. In these async dispatch paths, `$callers` (set by
  `Task` for every spawned task) preserves the caller chain back to the
  agent runner, allowing scope resolution without a global ETS scan.

  ## Usage

  Runners call `put/2` after creating the MCP server and `delete/1`
  in an `after` block:

      server = ClaudeAgentSDK.create_sdk_mcp_server(...)
      AgentRunScope.put(server.registry_pid, %{project_id: id, ...})
      try do
        # ... SDK query ...
      after
        AgentRunScope.delete(server.registry_pid)
      end

  Tool modules call `resolve_for_current_process/0` to retrieve scope.
  """

  @table __MODULE__
  @owner Spotter.Observability.AgentRunScopeOwner
  @registry_hint_key :claude_agent_sdk_tool_registry_pid

  @type scope_map :: %{
          optional(:project_id) => String.t(),
          optional(:commit_hash) => String.t(),
          optional(:git_cwd) => String.t() | nil,
          optional(:run_id) => String.t() | nil,
          optional(:agent_kind) => String.t()
        }

  @doc false
  def create_table do
    ensure_owner_started()
    :ok
  end

  @doc """
  Ensures the ETS table exists. Safe to call multiple times.
  """
  def ensure_table_exists, do: ensure_table()

  @doc """
  Stores a scope map keyed by the given registry pid.
  """
  @spec put(pid(), scope_map()) :: :ok
  def put(registry_pid, scope_map) when is_pid(registry_pid) and is_map(scope_map) do
    ensure_table()
    :ets.insert(@table, {registry_pid, scope_map})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Retrieves the scope map for the given registry pid.
  """
  @spec get(pid()) :: {:ok, scope_map()} | :error
  def get(registry_pid) when is_pid(registry_pid) do
    ensure_table()

    case :ets.lookup(@table, registry_pid) do
      [{^registry_pid, scope}] -> {:ok, scope}
      _ -> :error
    end
  end

  @doc """
  Removes the scope entry for the given registry pid.
  """
  @spec delete(pid()) :: :ok
  def delete(registry_pid) when is_pid(registry_pid) do
    ensure_table()
    :ets.delete(@table, registry_pid)
    :ok
  end

  @doc """
  Resolves the scope for the current process by inspecting process
  lineage (`$ancestors` and `$callers`) for a pid with scope in ETS.
  Fails closed with `{:error, :no_scope}` when no lineage pid has a
  matching entry — no global table scan is attempted.

  Returns `{:ok, scope_map}` or `{:error, :no_scope}`.
  """
  @spec resolve_for_current_process() :: {:ok, scope_map()} | {:error, :no_scope}
  def resolve_for_current_process do
    ensure_table()

    case resolve_via_registry_hint() do
      {:ok, _} = hit ->
        hit

      :error ->
        case resolve_via_lineage() do
          {:ok, _} = hit -> hit
          :error -> {:error, :no_scope}
        end
    end
  rescue
    _ -> {:error, :no_scope}
  end

  # Some SDK paths may provide the registry pid directly.
  defp resolve_via_registry_hint do
    case Process.get(@registry_hint_key) do
      pid when is_pid(pid) -> lookup_scope(pid)
      _ -> :error
    end
  end

  # Walk process lineage looking for a pid that has scope in ETS.
  defp resolve_via_lineage do
    candidates = Process.get(:"$ancestors", []) ++ Process.get(:"$callers", [])

    Enum.find_value(candidates, :error, fn candidate ->
      case lookup_scope(candidate) do
        {:ok, _} = hit -> hit
        :error -> nil
      end
    end)
  end

  defp lookup_scope(pid) when is_pid(pid) do
    case :ets.lookup(@table, pid) do
      [{^pid, scope}] -> {:ok, scope}
      _ -> :error
    end
  end

  defp lookup_scope(_), do: :error

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        ensure_owner_started()
        @owner.ensure_table_exists(@owner)

      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp ensure_owner_started do
    case Process.whereis(@owner) do
      nil ->
        case @owner.start_link(name: @owner) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, _reason} -> :ok
        end

      _pid ->
        :ok
    end
  end
end
