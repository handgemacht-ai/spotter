defmodule Spotter.Observability.ErrorReport do
  @moduledoc """
  Builds structured error payloads for FlowHub events and trace attributes.

  Every error payload includes at minimum:
  - `"error.type"` (stable machine string)
  - `"error.message"` (human-readable)
  - `"error.source"` (module or subsystem identifier)
  """

  @doc """
  Builds a structured error payload for hook flow events.

  Always includes `error.type`, `error.message`, `error.source`,
  `http.status_code`, `hook_event`, and `hook_script`.
  """
  @spec hook_flow_error(String.t(), String.t(), integer(), String.t(), String.t(), map()) ::
          map()
  def hook_flow_error(type, message, status_code, hook_event, hook_script, extras \\ %{}) do
    %{
      "error.type" => type,
      "error.message" => message,
      "error.source" => "hooks_controller",
      "http.status_code" => status_code,
      "hook_event" => hook_event,
      "hook_script" => hook_script
    }
    |> Map.merge(extras)
  end

  @doc """
  Builds structured error attributes for trace spans.

  Always includes `error.type`, `error.message`, and `error.source`.
  """
  @spec trace_error(String.t(), String.t(), String.t(), map()) :: map()
  def trace_error(type, message, source, extras \\ %{}) do
    %{
      "error.type" => type,
      "error.message" => message,
      "error.source" => source
    }
    |> Map.merge(extras)
  end

  @doc """
  Sets error status on the current trace span with structured attributes.

  Calls `Tracer.set_status(:error, message)` and sets `error.type`,
  `error.message`, and `error.source` as span attributes.
  """
  @spec set_trace_error(String.t(), String.t(), String.t(), map()) :: :ok
  def set_trace_error(type, message, source, extras \\ %{}) do
    require OpenTelemetry.Tracer, as: Tracer

    attrs = trace_error(type, message, source, extras)

    Enum.each(attrs, fn {k, v} ->
      Tracer.set_attribute(k, stringify(v))
    end)

    Tracer.set_status(:error, message)
    :ok
  rescue
    _ -> :ok
  end

  defp stringify(v) when is_binary(v), do: v
  defp stringify(v) when is_atom(v), do: Atom.to_string(v)
  defp stringify(v) when is_number(v), do: v
  defp stringify(v), do: inspect(v)
end
