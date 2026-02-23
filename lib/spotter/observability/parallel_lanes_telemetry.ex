defmodule Spotter.Observability.ParallelLanesTelemetry do
  @moduledoc """
  Telemetry handler for Parallel Transcript Lanes observability.

  Records metrics and error events for lane computation. Does not manage
  span lifecycle — the business logic in `Spotter.Transcripts.ParallelLanes`
  owns span creation via `Tracer.with_span`.
  """

  require Logger

  alias Spotter.Observability.ErrorReport

  @handler_id "spotter.observability.parallel_lanes_telemetry"

  @events [
    [:spotter, :parallel_lanes, :compute, :stop],
    [:spotter, :parallel_lanes, :compute, :error]
  ]

  @doc """
  Attach telemetry handlers for parallel lanes events.

  Safe to call multiple times; detaches existing handlers before re-attaching.
  """
  @spec setup() :: :ok
  def setup do
    :telemetry.detach(@handler_id)
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, %{})
    :ok
  rescue
    _error ->
      Logger.warning("ParallelLanesTelemetry: failed to attach telemetry handlers")
      :ok
  end

  @doc false
  def handle_event(
        [:spotter, :parallel_lanes, :compute, :stop],
        _measurements,
        _metadata,
        _config
      ) do
    :ok
  rescue
    _error -> :ok
  end

  def handle_event(
        [:spotter, :parallel_lanes, :compute, :error],
        _measurements,
        metadata,
        _config
      ) do
    reason = Map.get(metadata, :reason)
    message = if is_exception(reason), do: Exception.message(reason), else: inspect(reason)

    ErrorReport.set_trace_error(
      "parallel_lanes_compute_error",
      message,
      "telemetry.parallel_lanes",
      %{}
    )
  rescue
    _error -> :ok
  end
end
