defmodule SpotterWeb.InstructionsTelemetryLive do
  use Phoenix.LiveView

  alias Spotter.Services.InstructionsTelemetryQuery
  alias Spotter.Transcripts.Project

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @telemetry_topic_prefix "instructions_telemetry:project:"

  def telemetry_topic(project_id), do: @telemetry_topic_prefix <> to_string(project_id)

  @windows %{
    "last_24h" => :last_24h,
    "last_7d" => :last_7d,
    "last_30d" => :last_30d,
    "all" => :all
  }
  @path_truncate_length 60
  @debounce_ms 300

  @impl true
  def mount(_params, _session, socket) do
    projects =
      try do
        Project |> Ash.Query.sort(name: :asc) |> Ash.read!()
      rescue
        e ->
          Logger.warning("Failed to load projects: #{Exception.message(e)}")
          []
      end

    first_pid = first_project_id(projects)

    if connected?(socket) do
      :timer.send_interval(5000, :tick)
      if first_pid, do: subscribe_telemetry(first_pid)
    end

    {:ok,
     assign(socket,
       projects: projects,
       selected_project_id: first_pid,
       selected_window: :last_7d,
       data: empty_data(),
       debounce_ref: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id =
      normalize_project_id(socket.assigns.projects, parse_project_id(params["project_id"]))

    window = parse_window(params["window"])
    old_pid = socket.assigns.selected_project_id

    if connected?(socket) and project_id != old_pid do
      if old_pid, do: unsubscribe_telemetry(old_pid)
      if project_id, do: subscribe_telemetry(project_id)
    end

    socket =
      socket
      |> assign(selected_project_id: project_id, selected_window: window)
      |> load_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = normalize_project_id(socket.assigns.projects, parse_project_id(raw_id))
    {:noreply, push_patch(socket, to: build_path(project_id, socket.assigns.selected_window))}
  end

  @impl true
  def handle_event("select_window", %{"window" => raw_window}, socket) do
    window = parse_window(raw_window)
    {:noreply, push_patch(socket, to: build_path(socket.assigns.selected_project_id, window))}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, load_data(socket)}
  end

  def handle_info({:instructions_telemetry_updated, %{project_id: pid}}, socket) do
    if pid == socket.assigns.selected_project_id do
      {:noreply, schedule_debounce(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:debounced_refresh, socket) do
    socket =
      Tracer.with_span "spotter.instructions_telemetry.live_refresh" do
        socket |> assign(debounce_ref: nil) |> load_data()
      end

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp load_data(socket) do
    %{selected_project_id: pid, selected_window: window} = socket.assigns

    data =
      if pid do
        InstructionsTelemetryQuery.query(pid, window: window)
      else
        empty_data()
      end

    assign(socket, data: data)
  end

  defp empty_data do
    %{
      summary: %{
        total_loads: 0,
        unique_documents: 0,
        unique_sessions: 0,
        total_bytes: 0,
        total_lines: 0
      },
      documents: [],
      sessions: []
    }
  end

  defp subscribe_telemetry(project_id) do
    Phoenix.PubSub.subscribe(Spotter.PubSub, telemetry_topic(project_id))
  end

  defp unsubscribe_telemetry(project_id) do
    Phoenix.PubSub.unsubscribe(Spotter.PubSub, telemetry_topic(project_id))
  end

  defp schedule_debounce(socket) do
    if socket.assigns.debounce_ref, do: Process.cancel_timer(socket.assigns.debounce_ref)
    ref = Process.send_after(self(), :debounced_refresh, @debounce_ms)
    assign(socket, debounce_ref: ref)
  end

  defp parse_project_id("all"), do: nil
  defp parse_project_id(nil), do: nil
  defp parse_project_id(""), do: nil
  defp parse_project_id(id), do: id

  defp normalize_project_id(projects, project_id) do
    first = first_project_id(projects)

    case project_id do
      nil -> first
      _ -> if Enum.any?(projects, &(&1.id == project_id)), do: project_id, else: first
    end
  end

  defp first_project_id(projects), do: List.first(projects) |> then(&(&1 && &1.id))

  defp parse_window(w) when is_map_key(@windows, w), do: Map.fetch!(@windows, w)
  defp parse_window(_), do: :last_7d

  defp build_path(project_id, window) do
    base =
      if project_id,
        do: "/projects/#{project_id}/telemetry/instructions",
        else: "/telemetry/instructions"

    if window == :last_7d, do: base, else: "#{base}?window=#{window}"
  end

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  defp format_bytes(bytes) when is_integer(bytes) and bytes >= 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end

  defp format_bytes(bytes) when is_integer(bytes), do: "#{bytes} B"
  defp format_bytes(_), do: "\u2014"

  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(_), do: "\u2014"

  defp truncate_path(path) when byte_size(path) > @path_truncate_length do
    keep = @path_truncate_length - 1
    "\u2026" <> String.slice(path, -keep, keep)
  end

  defp truncate_path(path), do: path

  defp relative_time(nil), do: "\u2014"

  defp relative_time(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="page-header">
        <h1>Instructions telemetry</h1>
      </div>

      <%!-- project filter --%>
      <div class="filter-section">
        <div>
          <label class="filter-label">project</label>
          <div class="filter-bar">
            <button
              :for={project <- @projects}
              phx-click="filter_project"
              phx-value-project-id={project.id}
              class={"filter-btn#{if @selected_project_id == project.id, do: " is-active"}"}
            >
              {project.name}
            </button>
          </div>
        </div>
      </div>

      <%!-- window selector --%>
      <div class="filter-section">
        <div>
          <label class="filter-label">window</label>
          <div class="filter-bar">
            <button
              :for={
                {window, label} <- [
                  {:last_24h, "24h"},
                  {:last_7d, "7d"},
                  {:last_30d, "30d"},
                  {:all, "All"}
                ]
              }
              phx-click="select_window"
              phx-value-window={Atom.to_string(window)}
              class={"filter-btn#{if @selected_window == window, do: " is-active"}"}
            >
              {label}
            </button>
          </div>
        </div>
      </div>

      <%!-- summary metrics --%>
      <div class="telemetry-summary" data-testid="summary-metrics">
        <div class="telemetry-metric-card">
          <span class="telemetry-metric-label">loads</span>
          <span class="telemetry-metric-value">{format_number(@data.summary.total_loads)}</span>
        </div>
        <div class="telemetry-metric-card">
          <span class="telemetry-metric-label">documents</span>
          <span class="telemetry-metric-value">
            {format_number(@data.summary.unique_documents)}
          </span>
        </div>
        <div class="telemetry-metric-card">
          <span class="telemetry-metric-label">sessions</span>
          <span class="telemetry-metric-value">
            {format_number(@data.summary.unique_sessions)}
          </span>
        </div>
        <div class="telemetry-metric-card">
          <span class="telemetry-metric-label">bytes</span>
          <span class="telemetry-metric-value">{format_bytes(@data.summary.total_bytes)}</span>
        </div>
        <div class="telemetry-metric-card">
          <span class="telemetry-metric-label">lines</span>
          <span class="telemetry-metric-value">{format_number(@data.summary.total_lines)}</span>
        </div>
      </div>

      <%!-- documents table --%>
      <div class="section">
        <h2>Documents</h2>
        <%= if @data.documents == [] do %>
          <div class="empty-state">No instruction data for the selected window.</div>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>file</th>
                <th>loads</th>
                <th>sessions</th>
                <th>bytes</th>
                <th>lines</th>
                <th>last_seen</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={doc <- @data.documents}>
                <td title={doc.file_path} class="command-cell">
                  <code>{truncate_path(doc.file_path)}</code>
                </td>
                <td>{doc.load_count}</td>
                <td>{doc.session_count}</td>
                <td>{format_bytes(doc.total_bytes)}</td>
                <td>{format_number(doc.total_lines)}</td>
                <td>{relative_time(doc.last_seen_at)}</td>
              </tr>
            </tbody>
          </table>
        <% end %>
      </div>

      <%!-- sessions table --%>
      <div class="section">
        <h2>Sessions</h2>
        <%= if @data.sessions == [] do %>
          <div class="empty-state">No session-linked instruction data for the selected window.</div>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>session</th>
                <th>loads</th>
                <th>documents</th>
                <th>bytes</th>
                <th>lines</th>
                <th>last_seen</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={sess <- @data.sessions}>
                <td class="command-cell">
                  <code>{String.slice(sess.external_session_id, 0, 12)}</code>
                </td>
                <td>{sess.load_count}</td>
                <td>{sess.document_count}</td>
                <td>{format_bytes(sess.total_bytes)}</td>
                <td>{format_number(sess.total_lines)}</td>
                <td>{relative_time(sess.last_seen_at)}</td>
              </tr>
            </tbody>
          </table>
        <% end %>
      </div>
    </div>
    """
  end
end
