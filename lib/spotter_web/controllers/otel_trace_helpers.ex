defmodule SpotterWeb.OtelTraceHelpers do
  @moduledoc """
  Helpers for instrumenting controllers with OpenTelemetry tracing.

  Provides utilities for creating spans, recording errors, and adding trace context
  to HTTP responses.
  """

  require OpenTelemetry.Tracer, as: Tracer
  import Plug.Conn

  alias Spotter.Telemetry.TraceContext

  @doc """
  Create a span with the given name and attributes, executing a block within it.

  Returns the result of the block. Never raises even if span creation fails.

  ## Example

      with_span "my.operation", %{"key" => "value"} do
        # your code here
      end
  """
  defmacro with_span(name, attrs \\ %{}, do: block) do
    quote do
      try do
        require OpenTelemetry.Tracer

        OpenTelemetry.Tracer.with_span unquote(name), %{} do
          SpotterWeb.OtelTraceHelpers.set_attributes_safely(unquote(attrs))
          unquote(block)
        end
      rescue
        _error -> unquote(block)
      end
    end
  end

  @doc false
  def set_attributes_safely(attrs) when is_map(attrs) do
    Enum.each(attrs, fn {key, value} ->
      try do
        Tracer.set_attribute(key, value)
      rescue
        _error -> :ok
      end
    end)
  end

  @doc """
  Add the current trace ID to the response headers if a trace context exists.

  Adds the `x-spotter-trace-id` header to the connection.
  """
  @spec put_trace_response_header(Plug.Conn.t()) :: Plug.Conn.t()
  def put_trace_response_header(conn) do
    case current_trace_id() do
      nil -> conn
      trace_id -> put_resp_header(conn, "x-spotter-trace-id", trace_id)
    end
  end

  @doc """
  Set error status on the current span with a reason and optional attributes.

  The reason should be a machine-readable atom or string. Attributes are merged
  with the span's existing attributes. Never raises if no current span exists.
  """
  @spec set_error(atom() | String.t(), map()) :: :ok
  def set_error(reason, attrs \\ %{}) when is_map(attrs) do
    try do
      reason_str = reason_to_string(reason)

      error_attrs =
        %{
          "error.type" => reason_str,
          "error.message" => reason_str,
          "error.source" => "unknown"
        }
        |> Map.merge(attrs)

      set_attributes_safely(error_attrs)
      Tracer.set_status(:error, reason_str)
    rescue
      _error -> :ok
    end

    :ok
  end

  @doc """
  Return a map with trace context keys suitable for merging into job args.

  Adds `:otel_trace_id` and `:otel_traceparent` when the corresponding values
  are available from the current span context. Returns an empty map when no
  trace is active.
  """
  @spec maybe_add_trace_context(map()) :: map()
  def maybe_add_trace_context(args) when is_map(args) do
    args
    |> maybe_put_trace_id()
    |> maybe_put_traceparent()
  end

  defp maybe_put_trace_id(args) do
    case current_trace_id() do
      nil -> args
      trace_id -> Map.put(args, :otel_trace_id, trace_id)
    end
  end

  defp maybe_put_traceparent(args) do
    case TraceContext.current_traceparent() do
      nil -> args
      traceparent -> Map.put(args, :otel_traceparent, traceparent)
    end
  end

  @doc """
  Return the current trace ID as a hex string, or nil if no trace is active.
  """
  @spec current_trace_id() :: String.t() | nil
  def current_trace_id do
    span_ctx = Tracer.current_span_ctx()

    case :otel_span.hex_trace_id(span_ctx) do
      "" -> nil
      hex -> hex
    end
  rescue
    _error -> nil
  end

  defp reason_to_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_to_string(reason) when is_binary(reason), do: reason
  defp reason_to_string(reason), do: inspect(reason)
end
