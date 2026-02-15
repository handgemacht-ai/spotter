defmodule Spotter.Observability.ObanTelemetry do
  @moduledoc """
  Telemetry handler that emits FlowHub events for Oban job lifecycle.

  Attaches to `[:oban, :job, :start | :stop | :exception]` and records
  flow events with job metadata, derived flow keys, and duration.
  """

  require Logger

  alias Spotter.Observability.FlowHub
  alias Spotter.Observability.FlowKeys

  @handler_id "spotter.observability.oban_telemetry"

  @events [
    [:oban, :job, :start],
    [:oban, :job, :stop],
    [:oban, :job, :exception]
  ]

  @doc """
  Attach telemetry handlers for Oban job events.

  Safe to call multiple times; detaches existing handlers before re-attaching.
  """
  @spec setup() :: :ok
  def setup do
    :telemetry.detach(@handler_id)
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, %{})
    :ok
  rescue
    _ ->
      Logger.warning("ObanTelemetry: failed to attach telemetry handlers")
      :ok
  end

  @doc false
  def handle_event([:oban, :job, :start], _measurements, metadata, _config) do
    job = Map.get(metadata, :job, %{})
    args = get_args(job)

    FlowHub.record(
      %{
        kind: "oban.job.start",
        status: :running,
        flow_keys: flow_keys_for(job),
        summary: "Job started: #{worker_name(job)}",
        payload: start_payload(job)
      }
      |> maybe_put_trace_context(args)
    )
  rescue
    _ -> :ok
  end

  def handle_event([:oban, :job, :stop], measurements, metadata, _config) do
    job = Map.get(metadata, :job, %{})
    state = Map.get(metadata, :state)
    args = get_args(job)

    FlowHub.record(
      %{
        kind: "oban.job.stop",
        status: map_stop_status(state),
        flow_keys: flow_keys_for(job),
        summary: "Job #{state}: #{worker_name(job)}",
        payload: stop_payload(job, state, measurements)
      }
      |> maybe_put_trace_context(args)
    )
  rescue
    _ -> :ok
  end

  def handle_event([:oban, :job, :exception], measurements, metadata, _config) do
    job = Map.get(metadata, :job, %{})
    state = Map.get(metadata, :state)
    args = get_args(job)

    FlowHub.record(
      %{
        kind: "oban.job.exception",
        status: :error,
        flow_keys: flow_keys_for(job),
        summary: "Job exception: #{worker_name(job)}",
        payload: exception_payload(job, state, measurements, metadata)
      }
      |> maybe_put_trace_context(args)
    )
  rescue
    _ -> :ok
  end

  defp maybe_put_trace_context(event, args) do
    traceparent = args["otel_traceparent"]
    trace_id = args["otel_trace_id"]

    event
    |> then(fn e ->
      if is_binary(traceparent), do: Map.put(e, :traceparent, traceparent), else: e
    end)
    |> then(fn e -> if is_binary(trace_id), do: Map.put(e, :trace_id, trace_id), else: e end)
  end

  defp flow_keys_for(job) do
    job_id = get_job_id(job)
    base = if job_id, do: [FlowKeys.oban(to_string(job_id))], else: []
    args = get_args(job)
    base ++ FlowKeys.derive(args)
  end

  defp get_job_id(%{id: id}) when not is_nil(id), do: id
  defp get_job_id(%Oban.Job{id: id}) when not is_nil(id), do: id
  defp get_job_id(_), do: nil

  defp get_args(%{args: args}) when is_map(args), do: args
  defp get_args(%Oban.Job{args: args}) when is_map(args), do: args
  defp get_args(_), do: %{}

  defp worker_name(%{worker: w}) when is_binary(w), do: short_worker(w)
  defp worker_name(%Oban.Job{worker: w}) when is_binary(w), do: short_worker(w)
  defp worker_name(_), do: "unknown"

  defp short_worker(worker) do
    worker |> String.split(".") |> List.last()
  end

  defp start_payload(job) do
    %{
      "job_id" => get_job_id(job),
      "worker" => Map.get(job, :worker),
      "queue" => to_string(Map.get(job, :queue, "default")),
      "attempt" => Map.get(job, :attempt, 1)
    }
  end

  defp stop_payload(job, state, measurements) do
    start_payload(job)
    |> Map.put("state", to_string(state))
    |> Map.put("duration_ms", duration_ms(measurements))
  end

  defp exception_payload(job, state, measurements, metadata) do
    stop_payload(job, state, measurements)
    |> Map.put("kind", to_string(Map.get(metadata, :kind, :error)))
    |> Map.put("reason", truncate_reason(Map.get(metadata, :reason)))
  end

  defp duration_ms(%{duration: d}) when is_integer(d),
    do: System.convert_time_unit(d, :native, :millisecond)

  defp duration_ms(_), do: nil

  defp map_stop_status(:success), do: :ok
  defp map_stop_status(:failure), do: :error
  defp map_stop_status(:discard), do: :error
  defp map_stop_status(:cancelled), do: :ok
  defp map_stop_status(:snoozed), do: :ok
  defp map_stop_status(_), do: :unknown

  defp truncate_reason(nil), do: nil

  defp truncate_reason(reason) when is_exception(reason) do
    reason |> Exception.message() |> String.slice(0, 500)
  end

  defp truncate_reason(reason), do: reason |> inspect() |> String.slice(0, 500)
end
