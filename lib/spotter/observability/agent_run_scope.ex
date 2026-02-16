defmodule Spotter.Observability.AgentRunScope do
  @moduledoc """
  Shared ETS-based run scope for SDK tool-loop agents.

  Stores scope metadata keyed by the SDK MCP server registry pid,
  enabling tool execution tasks (spawned in separate processes via
  `ClaudeAgentSDK.TaskSupervisor`) to resolve their parent agent's
  scope without relying on process dictionary inheritance.

  Resolution is **fail-closed**: `resolve_for_current_process/0` only
  resolves scope via the calling process's `$ancestors` chain. If no
  ancestor pid has a matching ETS entry, `{:error, :no_scope}` is
  returned. There is no global table scan fallback, preventing
  cross-project scope leakage under concurrent agent runs.

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

  @type scope_map :: %{
          optional(:project_id) => String.t(),
          optional(:commit_hash) => String.t(),
          optional(:git_cwd) => String.t() | nil,
          optional(:run_id) => String.t() | nil,
          optional(:agent_kind) => String.t()
        }

  @doc false
  def create_table do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
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
  Resolves the scope for the current process by inspecting `$ancestors`
  for a pid with scope in ETS. Fails closed with `{:error, :no_scope}`
  when no ancestor has a matching entry — no global table scan is attempted.

  Returns `{:ok, scope_map}` or `{:error, :no_scope}`.
  """
  @spec resolve_for_current_process() :: {:ok, scope_map()} | {:error, :no_scope}
  def resolve_for_current_process do
    ensure_table()

    case resolve_via_ancestors() do
      {:ok, _} = hit -> hit
      :error -> {:error, :no_scope}
    end
  rescue
    _ -> {:error, :no_scope}
  end

  # Walk $ancestors looking for a pid that has scope stored in ETS.
  defp resolve_via_ancestors do
    ancestors = Process.get(:"$ancestors", [])

    Enum.find_value(ancestors, :error, fn
      pid when is_pid(pid) ->
        case :ets.lookup(@table, pid) do
          [{^pid, scope}] -> {:ok, scope}
          _ -> nil
        end

      _name ->
        nil
    end)
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> create_table()
      _ -> :ok
    end
  rescue
    ArgumentError -> :ok
  end
end
