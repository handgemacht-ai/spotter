defmodule SpotterWeb.FlowsLive do
  @moduledoc """
  Live DAG visualization of flow events across hooks, Oban jobs, and agent runs.
  """
  use Phoenix.LiveView

  alias Spotter.Observability.FlowGraph
  alias Spotter.Observability.FlowHub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Spotter.PubSub, FlowHub.global_topic())
    end

    {graph, events} = build_graph()

    {:ok,
     socket
     |> assign(
       show_completed: false,
       selected_node: nil,
       graph: graph,
       events: events
     )
     |> push_graph()}
  end

  @impl true
  def handle_info({:flow_event, _event}, socket) do
    {graph, events} = build_graph()

    {:noreply,
     socket
     |> assign(graph: graph, events: events)
     |> push_graph()}
  end

  @impl true
  def handle_event("toggle_completed", _params, socket) do
    show_completed = !socket.assigns.show_completed

    {:noreply,
     socket
     |> assign(show_completed: show_completed)
     |> push_graph()}
  end

  def handle_event("flow_node_selected", %{"node_id" => node_id}, socket) do
    node = Enum.find(socket.assigns.graph.nodes, &(&1.id == node_id))
    {:noreply, assign(socket, selected_node: node)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_node: nil)}
  end

  defp build_graph do
    %{events: events} = FlowHub.snapshot(minutes: 120)
    graph = FlowGraph.build(events)
    {graph, events}
  rescue
    _ -> {%{nodes: [], edges: [], flows: []}, []}
  end

  defp push_graph(socket) do
    graph = socket.assigns.graph
    show_completed = socket.assigns.show_completed

    visible_flows =
      if show_completed do
        graph.flows
      else
        Enum.reject(graph.flows, & &1.completed?)
      end

    visible_keys = MapSet.new(Enum.map(visible_flows, & &1.flow_key))

    visible_nodes =
      if show_completed do
        graph.nodes
      else
        Enum.filter(graph.nodes, fn node ->
          Enum.any?(node.flow_keys, &MapSet.member?(visible_keys, &1))
        end)
      end

    visible_node_ids = MapSet.new(Enum.map(visible_nodes, & &1.id))

    visible_edges =
      Enum.filter(graph.edges, fn edge ->
        MapSet.member?(visible_node_ids, edge.from) and
          MapSet.member?(visible_node_ids, edge.to)
      end)

    push_event(socket, "flow_graph_update", %{
      nodes:
        Enum.map(visible_nodes, fn node ->
          %{
            id: node.id,
            type: node.type,
            label: node.label,
            status: to_string(node.status),
            trace_id: node.trace_id
          }
        end),
      edges:
        Enum.map(visible_edges, fn edge ->
          %{from: edge.from, to: edge.to}
        end)
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="page-header">
        <div style="display:flex;align-items:center;justify-content:space-between;">
          <div>
            <h1>Flows</h1>
            <p class="text-muted text-sm">Live event flow across hooks, jobs, and agents</p>
          </div>
          <div style="display:flex;gap:var(--space-2);align-items:center;">
            <span class="text-muted text-sm">
              <%= length(@graph.nodes) %> nodes, <%= length(@graph.edges) %> edges
            </span>
            <label class="flows-toggle">
              <input
                type="checkbox"
                checked={@show_completed}
                phx-click="toggle_completed"
              />
              Show completed
            </label>
          </div>
        </div>
      </div>

      <div class="flows-layout">
        <div class="flows-canvas" id="flow-graph" phx-hook="FlowGraph" phx-update="ignore">
        </div>

        <div class={"flows-panel #{if @selected_node, do: "is-open", else: ""}"}>
          <%= if @selected_node do %>
            <div class="flows-panel-header">
              <h3><%= @selected_node.label %></h3>
              <button class="btn btn-sm btn-ghost" phx-click="clear_selection">
                &times;
              </button>
            </div>
            <div class="flows-panel-body">
              <dl class="flows-detail-list">
                <dt>ID</dt>
                <dd><code><%= @selected_node.id %></code></dd>
                <dt>Type</dt>
                <dd><%= @selected_node.type %></dd>
                <dt>Status</dt>
                <dd>
                  <span class={"flows-status flows-status--#{@selected_node.status}"}>
                    <%= @selected_node.status %>
                  </span>
                </dd>
                <%= if @selected_node.trace_id do %>
                  <dt>Trace ID</dt>
                  <dd>
                    <code><%= String.slice(@selected_node.trace_id, 0, 16) %>...</code>
                    <a
                      href={"http://localhost:16686/trace/#{@selected_node.trace_id}"}
                      target="_blank"
                      class="flows-jaeger-link"
                    >
                      View in Jaeger
                    </a>
                  </dd>
                <% end %>
              </dl>
            </div>
          <% else %>
            <div class="flows-panel-empty">
              <p class="text-muted text-sm">Select a node to see details</p>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end
