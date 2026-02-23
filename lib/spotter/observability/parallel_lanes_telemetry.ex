defmodule Spotter.Observability.ParallelLanesTelemetry do
  @moduledoc """
  Telemetry handler for Parallel Transcript Lanes observability.

  Creates OpenTelemetry spans for lane computation and mode-switch events.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Observability.ErrorReport

  @handler_id "spotter.observability.parallel_lanes_telemetry"

  @events [
    [:spotter, :parallel_lanes, :compute, :start],
    [:spotter, :parallel_lanes, :compute, :stop],
    [:spotter, :parallel_lanes, :compute, :exception],
    [:spotter, :parallel_lanes, :mode_switch, :start],
    [:spotter, :parallel_lanes, :mode_switch, :stop],
    [:spotter, :parallel_lanes, :mode_switch, :exception]
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
        [:spotter, :parallel_lanes, :compute, :start],
        _measurements,
        metadata,
        _config
      ) do
    span_ctx =
      Tracer.start_span("spotter.parallel_lanes.compute", %{
        attributes: %{
          "spotter.parallel_lanes.lane_count" => Map.get(metadata, :lane_count, 0),
          "spotter.parallel_lanes.overlap_count" => Map.get(metadata, :overlap_count, 0),
          "spotter.parallel_lanes.team_id" => to_string(Map.get(metadata, :team_id, ""))
        }
      })

    Tracer.set_current_span(span_ctx)
  rescue
    _error -> :ok
  end

  def handle_event(
        [:spotter, :parallel_lanes, :compute, :stop],
        _measurements,
        _metadata,
        _config
      ) do
    Tracer.end_span()
  rescue
    _error -> :ok
  end

  def handle_event(
        [:spotter, :parallel_lanes, :compute, :exception],
        _measurements,
        metadata,
        _config
      ) do
    kind = Map.get(metadata, :kind, :error)
    reason = Map.get(metadata, :reason)
    message = if is_exception(reason), do: Exception.message(reason), else: inspect(reason)

    ErrorReport.set_trace_error(
      "parallel_lanes_compute_exception",
      message,
      "telemetry.parallel_lanes",
      %{"error.kind" => to_string(kind)}
    )

    Tracer.end_span()
  rescue
    _error -> :ok
  end

  def handle_event(
        [:spotter, :parallel_lanes, :mode_switch, :start],
        _measurements,
        metadata,
        _config
      ) do
    span_ctx =
      Tracer.start_span("spotter.parallel_lanes.mode_switch", %{
        attributes: %{
          "spotter.parallel_lanes.from_mode" => to_string(Map.get(metadata, :from_mode, "")),
          "spotter.parallel_lanes.to_mode" => to_string(Map.get(metadata, :to_mode, "")),
          "spotter.parallel_lanes.session_id" => to_string(Map.get(metadata, :session_id, ""))
        }
      })

    Tracer.set_current_span(span_ctx)
  rescue
    _error -> :ok
  end

  def handle_event(
        [:spotter, :parallel_lanes, :mode_switch, :stop],
        _measurements,
        _metadata,
        _config
      ) do
    Tracer.end_span()
  rescue
    _error -> :ok
  end

  def handle_event(
        [:spotter, :parallel_lanes, :mode_switch, :exception],
        _measurements,
        metadata,
        _config
      ) do
    kind = Map.get(metadata, :kind, :error)
    reason = Map.get(metadata, :reason)
    message = if is_exception(reason), do: Exception.message(reason), else: inspect(reason)

    ErrorReport.set_trace_error(
      "parallel_lanes_mode_switch_exception",
      message,
      "telemetry.parallel_lanes",
      %{"error.kind" => to_string(kind)}
    )

    Tracer.end_span()
  rescue
    _error -> :ok
  end
end
