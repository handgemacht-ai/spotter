defmodule Spotter.Observability.ClaudeAgentFlowTest do
  use ExUnit.Case, async: false

  alias Spotter.Observability.ClaudeAgentFlow
  alias Spotter.Observability.FlowEvent
  alias Spotter.Observability.FlowHub
  alias Spotter.Telemetry.TraceContext

  setup do
    if :ets.whereis(FlowHub) != :undefined do
      :ets.delete_all_objects(FlowHub)
    end

    :ok
  end

  # Make a synchronous call to FlowHub to ensure all prior casts have been processed
  defp flush_flow_hub do
    FlowHub.snapshot(minutes: 1)
    :ok
  end

  describe "TraceContext.current_traceparent/0" do
    test "returns nil when no span is active" do
      # Outside any span, should return nil
      assert is_nil(TraceContext.current_traceparent())
    end

    test "returns nil for current_trace_id when no span" do
      assert is_nil(TraceContext.current_trace_id())
    end
  end

  describe "wrap_stream/2" do
    test "emits agent.run.start and agent.run.stop" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      # Simulate a stream of messages (empty stream)
      []
      |> ClaudeAgentFlow.wrap_stream(run_id: "test-run-1")
      |> Enum.to_list()

      assert_receive {:flow_event, %FlowEvent{kind: "agent.run.start", status: :running}}, 1000
      assert_receive {:flow_event, %FlowEvent{kind: "agent.run.stop", status: :ok}}, 1000
    end

    test "passes through messages unchanged" do
      messages = [
        %{type: :message, data: "hello"},
        %{type: :message, data: "world"}
      ]

      result =
        messages
        |> ClaudeAgentFlow.wrap_stream(run_id: "test-passthrough")
        |> Enum.to_list()

      assert result == messages
    end

    test "emits agent.output.delta for text deltas" do
      stream_event = %{
        type: :stream_event,
        data: %{
          event: %{
            "type" => "content_block_delta",
            "delta" => %{"type" => "text_delta", "text" => "Hello world"}
          }
        }
      }

      [stream_event]
      |> ClaudeAgentFlow.wrap_stream(run_id: "test-delta")
      |> Enum.to_list()

      # Allow async GenServer.cast to be processed
      flush_flow_hub()

      %{events: events} = FlowHub.snapshot(minutes: 5)
      kinds = Enum.map(events, & &1.kind)

      assert "agent.run.start" in kinds
      assert "agent.output.delta" in kinds
      assert "agent.run.stop" in kinds

      delta = Enum.find(events, &(&1.kind == "agent.output.delta"))
      assert delta.payload["text"] == "Hello world"
    end

    test "emits agent.tool.start for tool use" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      stream_event = %{
        type: :stream_event,
        data: %{
          event: %{
            "type" => "content_block_start",
            "content_block" => %{
              "type" => "tool_use",
              "name" => "mcp__spec-tools__features_search",
              "id" => "tool-123"
            }
          }
        }
      }

      [stream_event]
      |> ClaudeAgentFlow.wrap_stream(run_id: "test-tool")
      |> Enum.to_list()

      assert_receive {:flow_event, %FlowEvent{kind: "agent.tool.start"} = event}, 1000
      assert event.payload["tool_name"] == "mcp__spec-tools__features_search"
      assert event.payload["tool_id"] == "tool-123"
    end

    test "emits agent.message.stop" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      stream_event = %{
        type: :stream_event,
        data: %{
          event: %{"type" => "message_stop"}
        }
      }

      [stream_event]
      |> ClaudeAgentFlow.wrap_stream(run_id: "test-msg-stop")
      |> Enum.to_list()

      assert_receive {:flow_event, %FlowEvent{kind: "agent.message.stop"}}, 1000
    end

    test "includes provided flow_keys" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      []
      |> ClaudeAgentFlow.wrap_stream(
        run_id: "test-keys",
        flow_keys: ["project:42", "commit:abc"]
      )
      |> Enum.to_list()

      assert_receive {:flow_event, %FlowEvent{kind: "agent.run.start"} = event}, 1000
      assert "agent_run:test-keys" in event.flow_keys
      assert "project:42" in event.flow_keys
      assert "commit:abc" in event.flow_keys
    end

    test "caps tool events at 200" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      tool_events =
        for i <- 1..210 do
          %{
            type: :stream_event,
            data: %{
              event: %{
                "type" => "content_block_start",
                "content_block" => %{
                  "type" => "tool_use",
                  "name" => "tool_#{i}",
                  "id" => "id-#{i}"
                }
              }
            }
          }
        end

      tool_events
      |> ClaudeAgentFlow.wrap_stream(run_id: "test-cap")
      |> Enum.to_list()

      %{events: events} = FlowHub.snapshot(minutes: 5)
      tool_starts = Enum.filter(events, &(&1.kind == "agent.tool.start"))
      assert length(tool_starts) == 200
    end
  end

  describe "build_opts/1" do
    test "enables include_partial_messages" do
      opts = ClaudeAgentFlow.build_opts(%ClaudeAgentSDK.Options{})
      assert opts.include_partial_messages == true
    end

    test "preserves existing env and options" do
      opts =
        ClaudeAgentFlow.build_opts(%ClaudeAgentSDK.Options{
          max_turns: 5,
          env: %{"FOO" => "bar"}
        })

      assert opts.max_turns == 5
      assert opts.env["FOO"] == "bar"
    end
  end
end
