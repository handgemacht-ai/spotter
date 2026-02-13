defmodule Spotter.Observability.FlowEvent do
  @moduledoc """
  Struct representing a single event in a flow visualization.

  Events are emitted by hook controllers, Oban telemetry, and agent runs,
  then stored in FlowHub for live DAG rendering on `/flows`.
  """

  @enforce_keys [:id, :inserted_at, :kind, :status, :flow_keys, :summary]
  defstruct [
    :id,
    :inserted_at,
    :kind,
    :status,
    :flow_keys,
    :summary,
    :traceparent,
    :trace_id,
    payload: %{}
  ]

  @type status :: :queued | :running | :ok | :error | :unknown

  @type t :: %__MODULE__{
          id: String.t(),
          inserted_at: DateTime.t(),
          kind: String.t(),
          status: status(),
          flow_keys: [String.t()],
          summary: String.t(),
          traceparent: String.t() | nil,
          trace_id: String.t() | nil,
          payload: map()
        }

  @max_summary_length 120
  @max_string_length 2_000
  @max_payload_chars 10_000

  @valid_statuses [:queued, :running, :ok, :error, :unknown]

  @doc """
  Builds a `%FlowEvent{}` from a map, applying sanitization and defaults.

  Accepts string or atom keys. Returns `{:ok, event}` or `{:error, reason}`.
  """
  @spec new(map()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) when is_map(attrs) do
    attrs = normalize_keys(attrs)

    with {:ok, kind} <- require_string(attrs, :kind),
         {:ok, flow_keys} <- require_flow_keys(attrs),
         {:ok, status} <- parse_status(attrs) do
      now = DateTime.utc_now()

      event = %__MODULE__{
        id: Map.get(attrs, :id) || generate_id(),
        inserted_at: Map.get(attrs, :inserted_at) || now,
        kind: kind,
        status: status,
        flow_keys: flow_keys,
        summary: attrs |> Map.get(:summary, kind) |> truncate(@max_summary_length),
        traceparent: Map.get(attrs, :traceparent),
        trace_id: derive_trace_id(attrs),
        payload: attrs |> Map.get(:payload, %{}) |> sanitize_payload()
      }

      {:ok, event}
    end
  end

  def new(_), do: {:error, "attrs must be a map"}

  @doc """
  Like `new/1` but returns the event directly or raises.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, event} -> event
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  defp normalize_keys(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  rescue
    ArgumentError -> Map.new(map, fn {k, v} -> {to_atom_safe(k), v} end)
  end

  defp to_atom_safe(k) when is_atom(k), do: k
  defp to_atom_safe(k) when is_binary(k), do: String.to_atom(k)

  defp require_string(attrs, key) do
    case Map.get(attrs, key) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, "#{key} is required and must be a non-empty string"}
    end
  end

  defp require_flow_keys(attrs) do
    case Map.get(attrs, :flow_keys) do
      keys when is_list(keys) and keys != [] ->
        {:ok, Enum.filter(keys, &is_binary/1)}

      _ ->
        {:error, "flow_keys is required and must be a non-empty list of strings"}
    end
  end

  defp parse_status(attrs) do
    case Map.get(attrs, :status, :unknown) do
      s when s in @valid_statuses -> {:ok, s}
      s when is_binary(s) -> parse_status_string(s)
      _ -> {:ok, :unknown}
    end
  end

  defp parse_status_string(s) do
    atom = String.to_existing_atom(s)
    if atom in @valid_statuses, do: {:ok, atom}, else: {:ok, :unknown}
  rescue
    ArgumentError -> {:ok, :unknown}
  end

  defp derive_trace_id(%{trace_id: trace_id}) when is_binary(trace_id), do: trace_id

  defp derive_trace_id(%{traceparent: traceparent}) when is_binary(traceparent) do
    case String.split(traceparent, "-") do
      [_version, trace_id, _span_id, _flags] when byte_size(trace_id) == 32 -> trace_id
      _ -> nil
    end
  end

  defp derive_trace_id(_), do: nil

  defp generate_id do
    # Time-sortable: microsecond timestamp + random suffix
    ts = System.system_time(:microsecond)
    rand = :crypto.strong_rand_bytes(4) |> Base.hex_encode32(case: :lower, padding: false)
    "evt-#{ts}-#{rand}"
  end

  defp sanitize_payload(payload) when is_map(payload) do
    payload
    |> Enum.map(fn {k, v} -> {k, truncate_value(v)} end)
    |> Enum.into(%{})
    |> enforce_payload_size()
  end

  defp sanitize_payload(_), do: %{}

  defp truncate_value(v) when is_binary(v), do: truncate(v, @max_string_length)
  defp truncate_value(v) when is_list(v), do: Enum.map(v, &truncate_value/1)

  defp truncate_value(v) when is_map(v) do
    Enum.map(v, fn {k, val} -> {k, truncate_value(val)} end) |> Enum.into(%{})
  end

  defp truncate_value(v), do: v

  defp truncate(str, max) when is_binary(str) and byte_size(str) > max do
    String.slice(str, 0, max) <> "..."
  end

  defp truncate(str, _max) when is_binary(str), do: str
  defp truncate(nil, _max), do: ""
  defp truncate(other, _max), do: to_string(other)

  defp enforce_payload_size(payload) do
    encoded = inspect(payload, limit: :infinity)

    if byte_size(encoded) > @max_payload_chars do
      %{"_truncated" => true, "_summary" => String.slice(encoded, 0, @max_payload_chars)}
    else
      payload
    end
  end
end
