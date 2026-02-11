defmodule Spotter.Services.SessionRegistry do
  @moduledoc false
  use GenServer

  @table __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def register(pane_id, session_id) do
    :ets.insert(@table, {pane_id, session_id})

    Phoenix.PubSub.broadcast(
      Spotter.PubSub,
      "pane_sessions",
      {:session_registered, pane_id, session_id}
    )

    :ok
  end

  def get_session_id(pane_id) do
    case :ets.lookup(@table, pane_id) do
      [{^pane_id, session_id}] -> session_id
      [] -> nil
    end
  end

  def get_pane_id(session_id) do
    case :ets.match(@table, {:"$1", session_id}) do
      [[pane_id] | _] -> pane_id
      _ -> nil
    end
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{}}
  end
end
