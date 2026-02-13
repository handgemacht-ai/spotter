defmodule Spotter.Observability.FlowHub do
  @moduledoc """
  In-memory event store for flow visualization.

  Stores bounded, time-windowed flow events in ETS and broadcasts
  incremental updates via PubSub. Events are emitted by hook controllers,
  Oban telemetry, and agent runs.

  ## Topics

  - `"flows:global"` — all events
  - `"flows:<flow_key>"` — events for a specific flow key
  """

  use GenServer

  alias Spotter.Observability.FlowEvent

  require Logger

  @table __MODULE__
  @sweep_interval :timer.seconds(30)
  @max_age_seconds 2 * 60 * 60
  @max_events 10_000
  @finished_timeout_seconds 60
  @default_snapshot_minutes 15

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a flow event. Non-blocking, never raises.

  Accepts a `%FlowEvent{}` or a map (which will be converted via `FlowEvent.new/1`).
  """
  @spec record(FlowEvent.t() | map()) :: :ok
  def record(%FlowEvent{} = event) do
    GenServer.cast(__MODULE__, {:record, event})
  rescue
    _ -> :ok
  end

  def record(attrs) when is_map(attrs) do
    case FlowEvent.new(attrs) do
      {:ok, event} -> record(event)
      {:error, _reason} -> :ok
    end
  rescue
    _ -> :ok
  end

  def record(_), do: :ok

  @doc """
  Returns recent events and flow summaries.

  ## Options

  - `:minutes` — lookback window (default #{@default_snapshot_minutes})
  - `:flow_key` — filter to a specific flow key
  """
  @spec snapshot(keyword()) :: %{events: [FlowEvent.t()], flows: [map()]}
  def snapshot(opts \\ []) do
    GenServer.call(__MODULE__, {:snapshot, opts})
  rescue
    _ -> %{events: [], flows: []}
  end

  @doc """
  Returns events for a specific flow key.
  """
  @spec events_for(String.t()) :: [FlowEvent.t()]
  def events_for(flow_key) when is_binary(flow_key) do
    GenServer.call(__MODULE__, {:events_for, flow_key})
  rescue
    _ -> []
  end

  @doc """
  Returns the PubSub topic for all flow events.
  """
  @spec global_topic() :: String.t()
  def global_topic, do: "flows:global"

  @doc """
  Returns the PubSub topic for a specific flow key.
  """
  @spec topic(String.t()) :: String.t()
  def topic(flow_key), do: "flows:#{flow_key}"

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :public, :ordered_set])
    Process.send_after(self(), :sweep, @sweep_interval)
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:record, %FlowEvent{} = event}, state) do
    store_event(event)
    broadcast(event)
    {:noreply, state}
  rescue
    error ->
      Logger.warning("FlowHub record failed: #{inspect(error)}")
      {:noreply, state}
  end

  @impl true
  def handle_call({:snapshot, opts}, _from, state) do
    minutes = Keyword.get(opts, :minutes, @default_snapshot_minutes)
    flow_key = Keyword.get(opts, :flow_key)
    cutoff = DateTime.add(DateTime.utc_now(), -minutes * 60, :second)

    events =
      list_events()
      |> Enum.filter(fn event ->
        DateTime.compare(event.inserted_at, cutoff) != :lt
      end)
      |> maybe_filter_flow_key(flow_key)

    flows = compute_flow_summaries(events)

    {:reply, %{events: events, flows: flows}, state}
  end

  def handle_call({:events_for, flow_key}, _from, state) do
    events =
      list_events()
      |> Enum.filter(fn event -> flow_key in event.flow_keys end)

    {:reply, events, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep_old_events()
    enforce_cap()
    Process.send_after(self(), :sweep, @sweep_interval)
    {:noreply, state}
  end

  # --- Internal ---

  defp store_event(%FlowEvent{} = event) do
    # Key: {inserted_at_unix_us, id} for ordered_set ordering
    key = {DateTime.to_unix(event.inserted_at, :microsecond), event.id}
    :ets.insert(@table, {key, event})
  end

  defp broadcast(%FlowEvent{} = event) do
    msg = {:flow_event, event}

    Phoenix.PubSub.broadcast(Spotter.PubSub, global_topic(), msg)

    Enum.each(event.flow_keys, fn flow_key ->
      Phoenix.PubSub.broadcast(Spotter.PubSub, topic(flow_key), msg)
    end)
  rescue
    _ -> :ok
  end

  defp list_events do
    :ets.tab2list(@table)
    |> Enum.map(fn {_key, event} -> event end)
    |> Enum.sort_by(fn event ->
      {DateTime.to_unix(event.inserted_at, :microsecond), event.id}
    end)
  end

  defp maybe_filter_flow_key(events, nil), do: events

  defp maybe_filter_flow_key(events, flow_key) do
    Enum.filter(events, fn event -> flow_key in event.flow_keys end)
  end

  defp sweep_old_events do
    cutoff_us =
      DateTime.utc_now()
      |> DateTime.add(-@max_age_seconds, :second)
      |> DateTime.to_unix(:microsecond)

    :ets.tab2list(@table)
    |> Enum.each(fn {{ts_us, _id} = key, _event} ->
      if ts_us < cutoff_us, do: :ets.delete(@table, key)
    end)
  end

  defp enforce_cap do
    count = :ets.info(@table, :size)

    if count > @max_events do
      to_remove = count - @max_events

      :ets.tab2list(@table)
      |> Enum.sort_by(fn {{ts_us, id}, _event} -> {ts_us, id} end)
      |> Enum.take(to_remove)
      |> Enum.each(fn {key, _event} -> :ets.delete(@table, key) end)
    end
  end

  @doc false
  def compute_flow_summaries(events) do
    now = DateTime.utc_now()

    events
    |> Enum.flat_map(fn event ->
      Enum.map(event.flow_keys, fn key -> {key, event} end)
    end)
    |> Enum.group_by(fn {key, _event} -> key end, fn {_key, event} -> event end)
    |> Enum.map(fn {flow_key, flow_events} ->
      last_seen = Enum.max_by(flow_events, &DateTime.to_unix(&1.inserted_at, :microsecond))
      seconds_since = DateTime.diff(now, last_seen.inserted_at, :second)

      all_terminal =
        flow_events
        |> Enum.filter(fn e -> e.status in [:queued, :running] end)
        |> Enum.empty?()

      completed = seconds_since >= @finished_timeout_seconds and all_terminal

      %{
        flow_key: flow_key,
        event_count: length(flow_events),
        last_seen_at: last_seen.inserted_at,
        completed?: completed,
        status: if(completed, do: :completed, else: :active)
      }
    end)
  end
end
