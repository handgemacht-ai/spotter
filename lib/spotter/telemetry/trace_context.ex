defmodule Spotter.Telemetry.TraceContext do
  @moduledoc """
  Helpers for extracting and formatting W3C trace context from OpenTelemetry spans.
  """

  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Returns the current W3C `traceparent` string, or `nil` if no span is active.

  Format: `00-<trace_id>-<span_id>-01`
  """
  @spec current_traceparent() :: String.t() | nil
  def current_traceparent do
    span_ctx = Tracer.current_span_ctx()
    trace_id = :otel_span.hex_trace_id(span_ctx)
    span_id = :otel_span.hex_span_id(span_ctx)

    if trace_id != "" and span_id != "" do
      "00-#{trace_id}-#{span_id}-01"
    end
  rescue
    _ -> nil
  end

  @doc """
  Returns the current trace ID as a 32-char hex string, or `nil`.
  """
  @spec current_trace_id() :: String.t() | nil
  def current_trace_id do
    span_ctx = Tracer.current_span_ctx()

    case :otel_span.hex_trace_id(span_ctx) do
      "" -> nil
      hex -> hex
    end
  rescue
    _ -> nil
  end
end
