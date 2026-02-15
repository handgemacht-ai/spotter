defmodule Spotter.Observability.FlowGraphTest do
  use ExUnit.Case, async: true

  alias Spotter.Observability.FlowEvent
  alias Spotter.Observability.FlowGraph

  defp make_event(attrs) do
    FlowEvent.new!(
      Map.merge(
        %{
          kind: "test",
          status: :ok,
          flow_keys: ["test:1"],
          summary: "Test"
        },
        attrs
      )
    )
  end

  describe "build/2 nodes" do
    test "creates nodes from flow keys" do
      events = [
        make_event(%{
          kind: "hook.commit_event.received",
          status: :running,
          flow_keys: ["session:s1", "commit:abc123"]
        })
      ]

      %{nodes: nodes} = FlowGraph.build(events)
      node_ids = Enum.map(nodes, & &1.id)

      assert "session:s1" in node_ids
      assert "commit:abc123" in node_ids
    end

    test "uses latest status for node" do
      events = [
        make_event(%{
          kind: "oban.job.start",
          status: :running,
          flow_keys: ["oban:42"],
          inserted_at: ~U[2026-01-01 00:00:00Z]
        }),
        make_event(%{
          kind: "oban.job.stop",
          status: :ok,
          flow_keys: ["oban:42"],
          inserted_at: ~U[2026-01-01 00:00:05Z]
        })
      ]

      %{nodes: nodes} = FlowGraph.build(events)
      oban_node = Enum.find(nodes, &(&1.id == "oban:42"))

      assert oban_node.status == :ok
    end

    test "labels commits with short hash" do
      events = [
        make_event(%{flow_keys: ["commit:abcdef1234567890abcdef1234567890abcdef12"]})
      ]

      %{nodes: nodes} = FlowGraph.build(events)
      commit_node = Enum.find(nodes, &(&1.type == "commit"))

      assert commit_node.label =~ "abcdef12"
    end

    test "labels oban nodes with worker name" do
      events = [
        make_event(%{
          kind: "oban.job.start",
          flow_keys: ["oban:42"],
          payload: %{"worker" => "EnrichCommits"}
        })
      ]

      %{nodes: nodes} = FlowGraph.build(events)
      oban_node = Enum.find(nodes, &(&1.id == "oban:42"))

      assert oban_node.label =~ "EnrichCommits"
    end

    test "filters out non-visual node types like project" do
      events = [
        make_event(%{
          flow_keys: ["session:s1", "project:1", "commit:abc"]
        })
      ]

      %{nodes: nodes} = FlowGraph.build(events)
      node_ids = Enum.map(nodes, & &1.id)

      assert "session:s1" in node_ids
      assert "commit:abc" in node_ids
      refute "project:1" in node_ids
    end

    test "extracts trace_id from events" do
      events = [
        make_event(%{
          flow_keys: ["session:s1"],
          traceparent: "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
        })
      ]

      %{nodes: nodes} = FlowGraph.build(events)
      session_node = Enum.find(nodes, &(&1.id == "session:s1"))

      assert session_node.trace_id == "0af7651916cd43dd8448eb211c80319c"
    end
  end

  describe "build/2 edges" do
    test "creates edges between nodes sharing an event" do
      events = [
        make_event(%{
          kind: "hook.commit_event.received",
          flow_keys: ["session:s1", "commit:abc"]
        })
      ]

      %{edges: edges} = FlowGraph.build(events)

      assert edges != []
      edge = hd(edges)
      assert edge.from == "session:s1"
      assert edge.to == "commit:abc"
    end

    test "creates chain: session -> commit -> oban -> agent" do
      events = [
        make_event(%{
          kind: "hook.received",
          flow_keys: ["session:s1", "commit:abc"]
        }),
        make_event(%{
          kind: "oban.enqueued",
          flow_keys: ["commit:abc", "oban:42"]
        }),
        make_event(%{
          kind: "agent.run.start",
          flow_keys: ["oban:42", "agent_run:run-1"]
        })
      ]

      %{edges: edges} = FlowGraph.build(events)
      edge_pairs = Enum.map(edges, fn e -> {e.from, e.to} end)

      assert {"session:s1", "commit:abc"} in edge_pairs
      assert {"commit:abc", "oban:42"} in edge_pairs
      assert {"oban:42", "agent_run:run-1"} in edge_pairs
    end

    test "creates only adjacent chain edges, not all pairs" do
      events = [
        make_event(%{
          flow_keys: ["session:s1", "commit:abc", "oban:42"]
        })
      ]

      %{edges: edges} = FlowGraph.build(events)
      edge_pairs = Enum.map(edges, fn e -> {e.from, e.to} end)

      assert {"session:s1", "commit:abc"} in edge_pairs
      assert {"commit:abc", "oban:42"} in edge_pairs
      refute {"session:s1", "oban:42"} in edge_pairs
      assert length(edges) == 2
    end

    test "does not create duplicate edges" do
      events = [
        make_event(%{flow_keys: ["session:s1", "commit:abc"]}),
        make_event(%{flow_keys: ["session:s1", "commit:abc"]})
      ]

      %{edges: edges} = FlowGraph.build(events)
      edge_pairs = Enum.map(edges, fn e -> {e.from, e.to} end)

      assert length(Enum.uniq(edge_pairs)) == length(edge_pairs)
    end
  end

  describe "build/2 flows and completion" do
    test "marks flow as active when recent" do
      now = ~U[2026-01-01 00:01:00Z]

      events = [
        make_event(%{
          flow_keys: ["session:s1"],
          status: :ok,
          inserted_at: ~U[2026-01-01 00:00:50Z]
        })
      ]

      %{flows: flows} = FlowGraph.build(events, now: now)
      flow = Enum.find(flows, &(&1.flow_key == "session:s1"))

      assert flow.completed? == false
      assert flow.status == :active
    end

    test "marks flow as completed when old and terminal" do
      now = ~U[2026-01-01 00:05:00Z]

      events = [
        make_event(%{
          flow_keys: ["session:s1"],
          status: :ok,
          inserted_at: ~U[2026-01-01 00:00:00Z]
        })
      ]

      %{flows: flows} = FlowGraph.build(events, now: now)
      flow = Enum.find(flows, &(&1.flow_key == "session:s1"))

      assert flow.completed? == true
      assert flow.status == :completed
    end

    test "keeps flow active when has running events even if old" do
      now = ~U[2026-01-01 00:05:00Z]

      events = [
        make_event(%{
          flow_keys: ["oban:42"],
          status: :running,
          inserted_at: ~U[2026-01-01 00:00:00Z]
        })
      ]

      %{flows: flows} = FlowGraph.build(events, now: now)
      flow = Enum.find(flows, &(&1.flow_key == "oban:42"))

      assert flow.completed? == false
    end

    test "full chain: hook -> commit -> oban -> agent yields correct completion" do
      now = ~U[2026-01-01 00:05:00Z]

      events = [
        make_event(%{
          kind: "hook.commit_event.ok",
          status: :ok,
          flow_keys: ["session:s1", "commit:abc"],
          inserted_at: ~U[2026-01-01 00:00:00Z]
        }),
        make_event(%{
          kind: "oban.job.stop",
          status: :ok,
          flow_keys: ["oban:42", "commit:abc"],
          inserted_at: ~U[2026-01-01 00:00:10Z]
        }),
        make_event(%{
          kind: "agent.run.stop",
          status: :ok,
          flow_keys: ["agent_run:run-1", "oban:42"],
          inserted_at: ~U[2026-01-01 00:00:20Z]
        })
      ]

      %{nodes: nodes, edges: edges, flows: flows} = FlowGraph.build(events, now: now)

      # All nodes present
      node_ids = Enum.map(nodes, & &1.id)
      assert "session:s1" in node_ids
      assert "commit:abc" in node_ids
      assert "oban:42" in node_ids
      assert "agent_run:run-1" in node_ids

      # Edges connect the chain
      assert edges != []

      # All flows should be completed (all terminal, > 60s old)
      Enum.each(flows, fn flow ->
        assert flow.completed? == true
      end)
    end
  end
end
