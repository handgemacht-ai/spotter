defmodule Spotter.Services.ReviewSessionRegistry do
  @moduledoc false
  use GenServer

  alias Spotter.Services.Tmux

  @table :review_session_registry
  @sweep_interval 15_000
  @ttl 30

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def register(name) do
    :ets.insert(@table, {name, System.monotonic_time(:second)})
    :ok
  end

  def heartbeat(name), do: register(name)

  def deregister(name) do
    :ets.delete(@table, name)
    Tmux.kill_session(name)
    :ok
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    Process.send_after(self(), :sweep, @sweep_interval)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:second)

    :ets.tab2list(@table)
    |> Enum.each(fn {name, last_heartbeat} ->
      if now - last_heartbeat > @ttl do
        :ets.delete(@table, name)
        Tmux.kill_session(name)
      end
    end)

    Process.send_after(self(), :sweep, @sweep_interval)
    {:noreply, state}
  end
end
