defmodule SpotterWeb.Telemetry.LiveviewOtel do
  @moduledoc """
  Telemetry handler that creates OpenTelemetry spans for LiveView lifecycle events.

  Attaches to Phoenix LiveView telemetry events and creates spans for mount,
  handle_params, and handle_event callbacks.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Observability.ErrorReport

  @handler_id __MODULE__

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
    Tracer.start_span(span_name, %{attributes: attrs})
  rescue
    _error -> :ok
  end

  def handle_event(
        [:phoenix, :live_view, _action, :stop],
        _measurements,
        _metadata,
        _config
      ) do
    Tracer.end_span()
  rescue
    _error -> :ok
  end

  def handle_event(
        [:phoenix, :live_view, _action, :exception],
        _measurements,
        metadata,
        _config
      ) do
    reason = Map.get(metadata, :kind, :error)

    ErrorReport.set_trace_error(
      "liveview_exception",
      to_string(reason),
      "telemetry.liveview_otel"
    )

    Tracer.end_span()
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
