defmodule SpotterWeb.FlowsLive do
  @moduledoc """
  Live DAG visualization of flow events across hooks, Oban jobs, and agent runs.
  """
  use Phoenix.LiveView

  alias Spotter.Observability.FlowGraph
  alias Spotter.Observability.FlowHub

  @refresh_debounce_ms 200
  @max_selected_events 200
  @max_output_bytes 64 * 1024

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
       selected_events: [],
       selected_output: nil,
       refresh_pending: false,
       graph: graph,
       events: events
     )
     |> push_graph()}
  end

  @impl true
  def handle_info({:flow_event, _event}, socket) do
    if socket.assigns.refresh_pending do
      {:noreply, socket}
    else
      Process.send_after(self(), :refresh_graph, @refresh_debounce_ms)
      {:noreply, assign(socket, refresh_pending: true)}
    end
  end

  def handle_info(:refresh_graph, socket) do
    {graph, events} = build_graph()

    selected_node =
      case socket.assigns.selected_node do
        nil -> nil
        prev -> Enum.find(graph.nodes, &(&1.id == prev.id))
      end

    {:noreply,
     socket
     |> assign(graph: graph, events: events, selected_node: selected_node, refresh_pending: false)
     |> load_selected_details()
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

    {:noreply,
     socket
     |> assign(selected_node: node)
     |> load_selected_details()}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_node: nil, selected_events: [], selected_output: nil)}
  end

  defp build_graph do
    %{events: events} = FlowHub.snapshot(minutes: 120)
    graph = FlowGraph.build(events)
    {graph, events}
  rescue
    _ -> {%{nodes: [], edges: [], flows: []}, []}
  end

  defp load_selected_details(%{assigns: %{selected_node: nil}} = socket) do
    assign(socket, selected_events: [], selected_output: nil)
  end

  defp load_selected_details(%{assigns: %{selected_node: node}} = socket) do
    node_events =
      node.id
      |> FlowHub.events_for()
      |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at, :microsecond), &1.id})
      |> Enum.take(-@max_selected_events)

    selected_output =
      if node.type == "agent_run" do
        output =
          node_events
          |> Enum.filter(&(&1.kind == "agent.output.delta"))
          |> Enum.map_join(fn e -> e.payload["text"] || "" end)

        if byte_size(output) > @max_output_bytes do
          binary_slice(output, byte_size(output) - @max_output_bytes, @max_output_bytes)
        else
          output
        end
      end

    assign(socket, selected_events: node_events, selected_output: selected_output)
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

        <div
          id="flows-panel"
          class={"flows-panel #{if @selected_node, do: "is-open", else: ""}"}
          phx-hook="PreserveScroll"
          data-scroll-key={(@selected_node && @selected_node.id) || ""}
        >
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

              <%= if @selected_output do %>
                <div class="flows-section">
                  <h4>Output</h4>
                  <pre class="flows-output" phx-no-format><code><%= @selected_output %></code></pre>
                </div>
              <% end %>

              <%= if @selected_events != [] do %>
                <div class="flows-section">
                  <h4>Events (<%= length(@selected_events) %>)</h4>
                  <div class="flows-event-timeline">
                    <div :for={event <- @selected_events} class="flows-event-item">
                      <div class="flows-event-meta">
                        <time class="text-muted text-xs">
                          <%= DateTime.to_iso8601(event.inserted_at) %>
                        </time>
                        <span class={"flows-status flows-status--#{event.status}"}>
                          <%= event.status %>
                        </span>
                      </div>
                      <div class="flows-event-kind"><%= event.kind %></div>
                      <div class="text-muted text-xs"><%= event.summary %></div>
                      <%= if event.payload && event.payload != %{} do %>
                        <details class="flows-event-payload">
                          <summary class="text-muted text-xs">payload</summary>
                          <pre class="text-xs"><%= inspect(event.payload, limit: 20, printable_limit: 200) %></pre>
                        </details>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
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
