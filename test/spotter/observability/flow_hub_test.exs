defmodule Spotter.Observability.FlowHubTest do
  use ExUnit.Case, async: false

  alias Spotter.Observability.FlowEvent
  alias Spotter.Observability.FlowHub
  alias Spotter.Observability.FlowKeys

  setup do
    # Clear ETS table between tests
    if :ets.whereis(FlowHub) != :undefined do
      :ets.delete_all_objects(FlowHub)
    end

    :ok
  end

  describe "record/1" do
    test "stores a FlowEvent struct" do
      {:ok, event} =
        FlowEvent.new(%{
          kind: "hook.commit.received",
          status: :ok,
          flow_keys: [FlowKeys.session("sess-1")],
          summary: "Commit hook received"
        })

      assert :ok = FlowHub.record(event)

      %{events: events} = FlowHub.snapshot()
      assert length(events) == 1
      assert hd(events).kind == "hook.commit.received"
    end

    test "stores from a raw map" do
      assert :ok =
               FlowHub.record(%{
                 kind: "oban.job.start",
                 status: :running,
                 flow_keys: [FlowKeys.oban("42")],
                 summary: "Job started"
               })

      %{events: events} = FlowHub.snapshot()
      assert length(events) == 1
      assert hd(events).kind == "oban.job.start"
    end

    test "never raises on invalid input" do
      assert :ok = FlowHub.record(nil)
      assert :ok = FlowHub.record("not a map")
      assert :ok = FlowHub.record(%{})
      assert :ok = FlowHub.record(%{kind: ""})
    end

    test "broadcasts on global topic" do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())

      FlowHub.record(%{
        kind: "test.broadcast",
        status: :ok,
        flow_keys: ["test:1"],
        summary: "Test"
      })

      assert_receive {:flow_event, %FlowEvent{kind: "test.broadcast"}}, 1000
    end

    test "broadcasts on per-flow-key topics" do
      flow_key = FlowKeys.session("abc")
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.topic(flow_key))

      FlowHub.record(%{
        kind: "test.per-key",
        status: :ok,
        flow_keys: [flow_key],
        summary: "Test"
      })

      assert_receive {:flow_event, %FlowEvent{kind: "test.per-key"}}, 1000
    end
  end

  describe "snapshot/1" do
    test "returns events within the time window" do
      FlowHub.record(%{
        kind: "recent",
        status: :ok,
        flow_keys: ["test:1"],
        summary: "Recent"
      })

      %{events: events} = FlowHub.snapshot(minutes: 15)
      assert length(events) == 1
      assert hd(events).kind == "recent"
    end

    test "filters by flow_key" do
      FlowHub.record(%{
        kind: "a",
        status: :ok,
        flow_keys: ["key:a"],
        summary: "A"
      })

      FlowHub.record(%{
        kind: "b",
        status: :ok,
        flow_keys: ["key:b"],
        summary: "B"
      })

      %{events: events} = FlowHub.snapshot(flow_key: "key:a")
      assert length(events) == 1
      assert hd(events).kind == "a"
    end

    test "returns flow summaries" do
      FlowHub.record(%{
        kind: "x",
        status: :ok,
        flow_keys: ["flow:1"],
        summary: "X"
      })

      FlowHub.record(%{
        kind: "y",
        status: :ok,
        flow_keys: ["flow:1"],
        summary: "Y"
      })

      %{flows: flows} = FlowHub.snapshot()
      flow = Enum.find(flows, &(&1.flow_key == "flow:1"))
      assert flow.event_count == 2
    end
  end

  describe "events_for/1" do
    test "returns events matching a flow key" do
      FlowHub.record(%{
        kind: "match",
        status: :ok,
        flow_keys: ["target:1", "other:2"],
        summary: "Match"
      })

      FlowHub.record(%{
        kind: "no-match",
        status: :ok,
        flow_keys: ["other:3"],
        summary: "No match"
      })

      events = FlowHub.events_for("target:1")
      assert length(events) == 1
      assert hd(events).kind == "match"
    end
  end

  describe "flow completion" do
    test "marks flows as completed when all terminal and timeout elapsed" do
      old_time = DateTime.add(DateTime.utc_now(), -120, :second)

      {:ok, event} =
        FlowEvent.new(%{
          kind: "done",
          status: :ok,
          flow_keys: ["old-flow:1"],
          summary: "Done"
        })

      # Override inserted_at to simulate old event
      event = %{event | inserted_at: old_time}
      FlowHub.record(event)

      %{flows: flows} = FlowHub.snapshot(minutes: 300)
      flow = Enum.find(flows, &(&1.flow_key == "old-flow:1"))
      assert flow.completed? == true
      assert flow.status == :completed
    end

    test "does not complete flows with running events" do
      old_time = DateTime.add(DateTime.utc_now(), -120, :second)

      {:ok, event} =
        FlowEvent.new(%{
          kind: "still-running",
          status: :running,
          flow_keys: ["active-flow:1"],
          summary: "Running"
        })

      event = %{event | inserted_at: old_time}
      FlowHub.record(event)

      %{flows: flows} = FlowHub.snapshot(minutes: 300)
      flow = Enum.find(flows, &(&1.flow_key == "active-flow:1"))
      assert flow.completed? == false
      assert flow.status == :active
    end
  end

  describe "FlowEvent" do
    test "sanitizes long summaries" do
      long_summary = String.duplicate("x", 200)

      {:ok, event} =
        FlowEvent.new(%{
          kind: "test",
          status: :ok,
          flow_keys: ["test:1"],
          summary: long_summary
        })

      assert String.length(event.summary) <= 123
    end

    test "sanitizes long payload strings" do
      long_val = String.duplicate("y", 5000)

      {:ok, event} =
        FlowEvent.new(%{
          kind: "test",
          status: :ok,
          flow_keys: ["test:1"],
          summary: "Test",
          payload: %{"big" => long_val}
        })

      assert byte_size(event.payload["big"]) <= 2003
    end

    test "derives trace_id from traceparent" do
      tp = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"

      {:ok, event} =
        FlowEvent.new(%{
          kind: "test",
          status: :ok,
          flow_keys: ["test:1"],
          summary: "Test",
          traceparent: tp
        })

      assert event.trace_id == "0af7651916cd43dd8448eb211c80319c"
    end

    test "handles unknown status gracefully" do
      {:ok, event} =
        FlowEvent.new(%{
          kind: "test",
          status: :banana,
          flow_keys: ["test:1"],
          summary: "Test"
        })

      assert event.status == :unknown
    end

    test "rejects missing kind" do
      assert {:error, _} =
               FlowEvent.new(%{
                 flow_keys: ["test:1"],
                 summary: "Test"
               })
    end

    test "rejects missing flow_keys" do
      assert {:error, _} =
               FlowEvent.new(%{
                 kind: "test",
                 summary: "Test"
               })
    end
  end

  describe "FlowKeys" do
    test "builds typed keys" do
      assert FlowKeys.session("abc") == "session:abc"
      assert FlowKeys.commit("dead") == "commit:dead"
      assert FlowKeys.project("1") == "project:1"
      assert FlowKeys.oban("42") == "oban:42"
      assert FlowKeys.agent_run("run-1") == "agent_run:run-1"
      assert FlowKeys.system() == "system"
    end

    test "derives keys from string-key map" do
      keys = FlowKeys.derive(%{"session_id" => "s1", "commit_hash" => "abc"})
      assert "session:s1" in keys
      assert "commit:abc" in keys
    end

    test "derives keys from atom-key map" do
      keys = FlowKeys.derive(%{session_id: "s1", project_id: "p1"})
      assert "session:s1" in keys
      assert "project:p1" in keys
    end

    test "handles empty and nil values" do
      assert FlowKeys.derive(%{"session_id" => ""}) == []
      assert FlowKeys.derive(%{"session_id" => nil}) == []
      assert FlowKeys.derive(nil) == []
    end
  end
end
