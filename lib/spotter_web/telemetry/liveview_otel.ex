defmodule SpotterWeb.Telemetry.LiveviewOtel do
  @moduledoc """
  Telemetry handler that creates OpenTelemetry spans for LiveView lifecycle events.

  Uses `OpentelemetryTelemetry` to manage span context via a tracer stack,
  preventing context leaks between sequential LiveView callbacks.
  """

  require Logger

  alias Spotter.Observability.ErrorReport

  @handler_id "spotter.telemetry.liveview_otel"
  @tracer_id @handler_id

  @events [
    [:phoenix, :live_view, :mount, :start],
    [:phoenix, :live_view, :mount, :stop],
    [:phoenix, :live_view, :mount, :exception],
    [:phoenix, :live_view, :handle_params, :start],
    [:phoenix, :live_view, :handle_params, :stop],
    [:phoenix, :live_view, :handle_params, :exception],
    [:phoenix, :live_view, :handle_event, :start],
    [:phoenix, :live_view, :handle_event, :stop],
    [:phoenix, :live_view, :handle_event, :exception]
  ]

  @doc """
  Attach telemetry handlers for LiveView events.

  Safe to call multiple times; detaches existing handlers before re-attaching.
  """
  @spec setup() :: :ok
  def setup do
    :telemetry.detach(@handler_id)
    # Detach OpentelemetryPhoenix's built-in LiveView handler to avoid
    # conflicting span context management on the same telemetry events
    :telemetry.detach({OpentelemetryPhoenix, :live_view})
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, %{})
    :ok
  rescue
    _error ->
      Logger.warning("LiveviewOtel: failed to attach telemetry handlers")
      :ok
  end

  @doc false
  def handle_event(
        [:phoenix, :live_view, action, :start],
        _measurements,
        metadata,
        _config
      ) do
    span_name = "spotter.liveview.#{action}"
    attrs = build_attributes(action, metadata)

    OpentelemetryTelemetry.start_telemetry_span(@tracer_id, span_name, metadata, %{
      attributes: attrs
    })
  rescue
    _error -> :ok
  end

  def handle_event(
        [:phoenix, :live_view, _action, :stop],
        _measurements,
        metadata,
        _config
      ) do
    OpentelemetryTelemetry.end_telemetry_span(@tracer_id, metadata)
  rescue
    _error -> :ok
  end

  def handle_event(
        [:phoenix, :live_view, _action, :exception],
        _measurements,
        metadata,
        _config
      ) do
    reason = Map.get(metadata, :reason)

    message =
      if is_exception(reason),
        do: Exception.message(reason),
        else: to_string(Map.get(metadata, :kind, :error))

    ErrorReport.set_trace_error(
      "liveview_exception",
      message,
      "telemetry.liveview_otel"
    )

    OpentelemetryTelemetry.end_telemetry_span(@tracer_id, metadata)
  rescue
    _error -> :ok
  end

  defp build_attributes(action, metadata) do
    module = metadata |> Map.get(:socket) |> get_view_module()

    attrs = %{
      "spotter.liveview.module" => module,
      "spotter.liveview.connected" => get_connected(metadata)
    }

    if action == :handle_event do
      Map.put(attrs, "spotter.liveview.event", Map.get(metadata, :event, "unknown"))
    else
      attrs
    end
  rescue
    _error -> %{}
  end

  defp get_view_module(%{view: module}) when is_atom(module), do: inspect(module)
  defp get_view_module(_), do: "unknown"

  defp get_connected(%{socket: %{transport_pid: pid}}) when is_pid(pid), do: true
  defp get_connected(_), do: false
end
