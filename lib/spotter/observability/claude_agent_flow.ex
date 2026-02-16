defmodule Spotter.Observability.ClaudeAgentFlow do
  @moduledoc """
  Wraps ClaudeAgentSDK query streams with FlowHub event emission.

  Emits flow events for agent lifecycle (start/stop/error), streaming text
  output (throttled), and tool use starts. Maintains a bounded ring buffer
  per agent run for the latest assistant text.
  """

  require Logger

  alias Spotter.Observability.FlowHub
  alias Spotter.Observability.FlowKeys
  alias Spotter.Telemetry.TraceContext

  @max_text_bytes 64 * 1024
  @max_tool_events 200
  @throttle_ms 50

  @doc """
  Wraps a ClaudeAgentSDK query stream with flow event emission.

  Returns a stream that yields the same messages as the original, but
  emits FlowHub events as a side effect.

  ## Options

  - `:flow_keys` — additional flow keys (e.g. `[FlowKeys.project("1")]`)
  - `:run_id` — unique ID for this agent run (auto-generated if not provided)
  - `:traceparent` — explicit W3C traceparent override (falls back to current span)
  """
  @spec wrap_stream(Enumerable.t(), keyword()) :: Enumerable.t()
  def wrap_stream(stream, opts \\ []) do
    run_id = Keyword.get(opts, :run_id) || generate_run_id()
    extra_keys = Keyword.get(opts, :flow_keys, [])
    flow_keys = [FlowKeys.agent_run(run_id) | extra_keys]
    traceparent = Keyword.get(opts, :traceparent) || TraceContext.current_traceparent()

    Stream.transform(
      stream,
      fn ->
        emit_start(run_id, flow_keys, traceparent)

        %{
          run_id: run_id,
          flow_keys: flow_keys,
          traceparent: traceparent,
          text_buffer: "",
          tool_event_count: 0,
          last_delta_at: System.monotonic_time(:millisecond) - @throttle_ms - 1
        }
      end,
      fn message, state ->
        state = process_message(message, state)
        {[message], state}
      end,
      fn state ->
        emit_stop(state)
      end
    )
  end

  @doc """
  Builds ClaudeAgentSDK options with streaming and trace propagation enabled.

  Merges the provided options with `include_partial_messages: true` and
  sets `TRACEPARENT` in the env when a trace is active.
  """
  @spec build_opts(ClaudeAgentSDK.Options.t()) :: ClaudeAgentSDK.Options.t()
  def build_opts(%ClaudeAgentSDK.Options{} = opts) do
    traceparent = TraceContext.current_traceparent()

    env =
      (opts.env || %{})
      |> maybe_put_traceparent(traceparent)

    %{opts | include_partial_messages: true, env: env}
  end

  @doc """
  Returns the ring buffer text for a given run (from FlowHub events).

  This is a convenience for the UI to show agent output preview.
  """
  @spec get_output_preview(String.t()) :: String.t()
  def get_output_preview(run_id) do
    flow_key = FlowKeys.agent_run(run_id)

    FlowHub.events_for(flow_key)
    |> Enum.filter(&(&1.kind == "agent.output.delta"))
    |> Enum.map_join(fn event -> Map.get(event.payload, "text", "") end)
    |> String.slice(0, @max_text_bytes)
  rescue
    _ -> ""
  end

  # --- Internal ---

  defp emit_start(run_id, flow_keys, traceparent) do
    FlowHub.record(%{
      kind: "agent.run.start",
      status: :running,
      flow_keys: flow_keys,
      summary: "Agent run started: #{run_id}",
      traceparent: traceparent,
      payload: %{"run_id" => run_id}
    })
  rescue
    _ -> :ok
  end

  defp emit_stop(%{run_id: run_id, flow_keys: flow_keys, traceparent: traceparent}) do
    FlowHub.record(%{
      kind: "agent.run.stop",
      status: :ok,
      flow_keys: flow_keys,
      summary: "Agent run completed: #{run_id}",
      traceparent: traceparent,
      payload: %{"run_id" => run_id}
    })
  rescue
    _ -> :ok
  end

  defp process_message(message, state) do
    case message do
      %{type: :stream_event, data: %{event: event}} when is_map(event) ->
        handle_stream_event(event, state)

      _ ->
        state
    end
  rescue
    _ -> state
  end

  defp handle_stream_event(event, state) do
    case event do
      %{"type" => "content_block_delta", "delta" => %{"type" => "text_delta", "text" => text}} ->
        handle_text_delta(text, state)

      %{"type" => "content_block_start", "content_block" => %{"type" => "tool_use"} = block} ->
        handle_tool_start(block, state)

      %{"type" => "message_stop"} ->
        handle_message_stop(state)

      _ ->
        state
    end
  end

  defp handle_text_delta(text, state) do
    new_buffer = truncate_buffer(state.text_buffer <> text)
    now = System.monotonic_time(:millisecond)

    state = %{state | text_buffer: new_buffer}

    if now - state.last_delta_at >= @throttle_ms do
      FlowHub.record(%{
        kind: "agent.output.delta",
        status: :running,
        flow_keys: state.flow_keys,
        traceparent: state.traceparent,
        summary: "Agent output (#{byte_size(new_buffer)} bytes)",
        payload: %{"text" => text, "buffer_size" => byte_size(new_buffer)}
      })

      %{state | last_delta_at: now}
    else
      state
    end
  rescue
    _ -> state
  end

  defp handle_tool_start(block, state) do
    if state.tool_event_count < @max_tool_events do
      tool_name = Map.get(block, "name", "unknown")
      tool_id = Map.get(block, "id", "unknown")

      FlowHub.record(%{
        kind: "agent.tool.start",
        status: :running,
        flow_keys: state.flow_keys,
        traceparent: state.traceparent,
        summary: "Tool: #{tool_name}",
        payload: %{"tool_name" => tool_name, "tool_id" => tool_id}
      })

      %{state | tool_event_count: state.tool_event_count + 1}
    else
      state
    end
  rescue
    _ -> state
  end

  defp handle_message_stop(state) do
    FlowHub.record(%{
      kind: "agent.message.stop",
      status: :ok,
      flow_keys: state.flow_keys,
      summary: "Agent message complete",
      payload: %{"run_id" => state.run_id}
    })

    state
  rescue
    _ -> state
  end

  defp truncate_buffer(buffer) when byte_size(buffer) > @max_text_bytes do
    binary_part(buffer, byte_size(buffer) - @max_text_bytes, @max_text_bytes)
  end

  defp truncate_buffer(buffer), do: buffer

  defp maybe_put_traceparent(env, nil), do: env
  defp maybe_put_traceparent(env, tp), do: Map.put(env, "TRACEPARENT", tp)

  defp generate_run_id do
    "run-#{System.system_time(:microsecond)}-#{:crypto.strong_rand_bytes(4) |> Base.hex_encode32(case: :lower, padding: false)}"
  end
end
