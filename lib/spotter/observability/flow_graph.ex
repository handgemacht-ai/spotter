defmodule Spotter.Observability.FlowGraph do
  @moduledoc """
  Converts FlowHub event snapshots into a stable, deterministic DAG model
  for the `/flows` LiveView.

  Nodes represent logical entities (sessions, commits, Oban jobs, agent runs).
  Edges represent causal relationships derived from shared flow keys.
  """

  alias Spotter.Observability.FlowEvent

  @finished_timeout_seconds 60

  @type_priority %{
    "session" => 0,
    "commit" => 1,
    "oban" => 2,
    "agent_run" => 3
  }

  @doc """
  Build a DAG from a list of flow events.

  Returns `%{nodes: [...], edges: [...], flows: [...]}`.

  ## Options

  - `:now` — override current time (for testing)
  """
  @spec build([FlowEvent.t()], keyword()) :: %{nodes: [map()], edges: [map()], flows: [map()]}
  def build(events, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    nodes = build_nodes(events)
    edges = build_edges(events, nodes)
    flows = build_flows(events, now)

    %{nodes: nodes, edges: edges, flows: flows}
  end

  # --- Nodes ---

  defp build_nodes(events) do
    events
    |> Enum.flat_map(fn event ->
      Enum.map(event.flow_keys, fn key -> {key, event} end)
    end)
    |> Enum.group_by(fn {key, _} -> key end, fn {_, event} -> event end)
    |> Enum.map(fn {node_id, node_events} ->
      latest = Enum.max_by(node_events, &DateTime.to_unix(&1.inserted_at, :microsecond))

      %{
        id: node_id,
        type: node_type(node_id),
        label: node_label(node_id, node_events),
        status: latest.status,
        inserted_at: earliest_time(node_events),
        flow_keys: [node_id],
        trace_id: find_trace_id(node_events)
      }
    end)
    |> Enum.sort_by(fn node ->
      {Map.get(@type_priority, node.type, 99), DateTime.to_unix(node.inserted_at, :microsecond)}
    end)
  end

  defp node_type(key) do
    case String.split(key, ":", parts: 2) do
      [type, _] -> type
      _ -> "unknown"
    end
  end

  defp node_label(node_id, events) do
    case node_type(node_id) do
      "session" ->
        "Session #{node_value(node_id)}"

      "commit" ->
        hash = node_value(node_id)
        "Commit #{String.slice(hash, 0, 8)}"

      "oban" ->
        worker =
          events
          |> Enum.find_value(fn e -> e.payload["worker"] end)

        "Job #{worker || node_value(node_id)}"

      "agent_run" ->
        "Agent #{node_value(node_id)}"

      _ ->
        node_id
    end
  end

  defp node_value(key) do
    case String.split(key, ":", parts: 2) do
      [_, value] -> value
      _ -> key
    end
  end

  defp earliest_time(events) do
    Enum.min_by(events, &DateTime.to_unix(&1.inserted_at, :microsecond)).inserted_at
  end

  defp find_trace_id(events) do
    Enum.find_value(events, fn event -> event.trace_id end)
  end

  # --- Edges ---

  defp build_edges(events, nodes) do
    node_ids = MapSet.new(Enum.map(nodes, & &1.id))

    events
    |> Enum.flat_map(fn event ->
      keys = Enum.filter(event.flow_keys, &MapSet.member?(node_ids, &1))

      sorted =
        Enum.sort_by(keys, fn key ->
          {Map.get(@type_priority, node_type(key), 99), key}
        end)

      pairs(sorted)
    end)
    |> Enum.uniq()
    |> Enum.map(fn {from, to} ->
      %{from: from, to: to, label: nil}
    end)
  end

  defp pairs([]), do: []
  defp pairs([_]), do: []

  defp pairs([a | rest]) do
    Enum.map(rest, fn b -> {a, b} end) ++ pairs(rest)
  end

  # --- Flows ---

  defp build_flows(events, now) do
    events
    |> Enum.flat_map(fn event ->
      Enum.map(event.flow_keys, fn key -> {key, event} end)
    end)
    |> Enum.group_by(fn {key, _} -> root_flow_key(key) end, fn {_, event} -> event end)
    |> Enum.map(fn {flow_key, flow_events} ->
      flow_events = Enum.uniq_by(flow_events, & &1.id)
      last_event = Enum.max_by(flow_events, &DateTime.to_unix(&1.inserted_at, :microsecond))
      seconds_since = DateTime.diff(now, last_event.inserted_at, :second)

      all_terminal =
        flow_events
        |> Enum.filter(fn e -> e.status in [:queued, :running] end)
        |> Enum.empty?()

      completed = seconds_since >= @finished_timeout_seconds and all_terminal

      %{
        flow_key: flow_key,
        status: if(completed, do: :completed, else: :active),
        last_seen_at: last_event.inserted_at,
        completed?: completed
      }
    end)
  end

  # Use the highest-priority (most root-like) key as the flow identifier
  defp root_flow_key(key) do
    type = node_type(key)

    if type in ["session", "commit"] do
      key
    else
      key
    end
  end
end
