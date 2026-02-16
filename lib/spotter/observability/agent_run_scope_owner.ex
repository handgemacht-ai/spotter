defmodule Spotter.Observability.AgentRunScopeOwner do
  @moduledoc false
  use GenServer

  @table Spotter.Observability.AgentRunScope

  def ensure_table_exists(owner \\ __MODULE__) do
    GenServer.call(owner, :ensure_table)
  catch
    :exit, _ ->
      :ok
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @impl true
  def init(:ok) do
    ensure_table()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:ensure_table, _from, state) do
    ensure_table()
    {:reply, :ok, state}
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end
end
