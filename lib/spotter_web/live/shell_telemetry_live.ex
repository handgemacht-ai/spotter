defmodule SpotterWeb.ShellTelemetryLive do
  use Phoenix.LiveView

  alias Spotter.Services.ShellCommandTelemetryQuery
  alias Spotter.Transcripts.Project

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @telemetry_topic_prefix "shell_telemetry:project:"

  def telemetry_topic(project_id), do: @telemetry_topic_prefix <> to_string(project_id)

  @windows %{
    "last_24h" => :last_24h,
    "last_7d" => :last_7d,
    "last_30d" => :last_30d,
    "all" => :all
  }
  @command_truncate_length 80
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
      :timer.send_interval(1000, :tick)
      if first_pid, do: subscribe_telemetry(first_pid)
    end

    {:ok,
     assign(socket,
       projects: projects,
       selected_project_id: first_pid,
       selected_window: :last_7d,
       commands: [],
       summary: empty_summary(),
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

  def handle_info({:shell_telemetry_updated, %{project_id: pid}}, socket) do
    if pid == socket.assigns.selected_project_id do
      {:noreply, schedule_debounce(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:debounced_refresh, socket) do
    socket =
      Tracer.with_span "spotter.shell_telemetry.live_refresh" do
        socket |> assign(debounce_ref: nil) |> load_data()
      end

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Data Loading ---

  defp load_data(socket) do
    %{selected_project_id: pid, selected_window: window} = socket.assigns

    commands =
      if pid do
        ShellCommandTelemetryQuery.snapshot(pid, window: window)
      else
        []
      end

    summary = compute_summary(commands)

    assign(socket, commands: commands, summary: summary)
  end

  defp compute_summary([]), do: empty_summary()

  defp compute_summary(commands) do
    total_completed = Enum.sum(Enum.map(commands, & &1.completed_count))
    total_errors = Enum.sum(Enum.map(commands, & &1.error_count))
    total_finished = total_completed + total_errors

    %{
      mean_ms: avg_field(commands, :mean_ms),
      median_ms: avg_field(commands, :median_ms),
      p50_ms: avg_field(commands, :p50_ms),
      p90_ms: avg_field(commands, :p90_ms),
      p95_ms: avg_field(commands, :p95_ms),
      error_rate: if(total_finished > 0, do: total_errors / total_finished, else: 0.0)
    }
  end

  defp avg_field(commands, field) do
    values = commands |> Enum.map(&Map.get(&1, field)) |> Enum.reject(&is_nil/1)
    if values == [], do: nil, else: Enum.sum(values) / length(values)
  end

  defp empty_summary do
    %{mean_ms: nil, median_ms: nil, p50_ms: nil, p90_ms: nil, p95_ms: nil, error_rate: 0.0}
  end

  # --- PubSub ---

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

  # --- Helpers ---

  defp parse_project_id("all"), do: nil
  defp parse_project_id(nil), do: nil
  defp parse_project_id(""), do: nil
  defp parse_project_id(id), do: id

  defp normalize_project_id(projects, project_id) do
    first = first_project_id(projects)

    case project_id do
      nil -> first
      _ -> if project_exists?(projects, project_id), do: project_id, else: first
    end
  end

  defp project_exists?(projects, project_id) do
    Enum.any?(projects, &(&1.id == project_id))
  end

  defp first_project_id(projects), do: List.first(projects) |> then(&(&1 && &1.id))

  defp parse_window(w) when is_map_key(@windows, w), do: Map.fetch!(@windows, w)
  defp parse_window(_), do: :last_7d

  defp build_path(project_id, window) do
    base =
      if project_id,
        do: "/projects/#{project_id}/telemetry/commands",
        else: "/telemetry/commands"

    if window == :last_7d, do: base, else: "#{base}?window=#{window}"
  end

  defp format_ms(nil), do: "\u2014"

  defp format_ms(ms) when is_number(ms) do
    cond do
      ms < 1000 -> "#{round(ms)}ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      true -> "#{Float.round(ms / 60_000, 1)}m"
    end
  end

  defp format_rate(rate) when is_number(rate) do
    "#{Float.round(rate * 100, 1)}%"
  end

  defp format_rate(_), do: "0.0%"

  defp truncate_command(cmd) when byte_size(cmd) > @command_truncate_length do
    String.slice(cmd, 0, @command_truncate_length) <> "\u2026"
  end

  defp truncate_command(cmd), do: cmd

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

  defp error_rate_class(rate) when rate >= 0.5, do: "badge badge-hot"
  defp error_rate_class(rate) when rate >= 0.2, do: "badge badge-warm"
  defp error_rate_class(rate) when rate > 0, do: "badge badge-mild"
  defp error_rate_class(_), do: "badge badge-cold"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="page-header">
        <h1>Command telemetry</h1>
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
              :for={{window, label} <- [{:last_24h, "24h"}, {:last_7d, "7d"}, {:last_30d, "30d"}, {:all, "All"}]}
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
          <span class="telemetry-metric-label">mean</span>
          <span class="telemetry-metric-value">{format_ms(@summary.mean_ms)}</span>
        </div>
        <div class="telemetry-metric-card">
          <span class="telemetry-metric-label">median</span>
          <span class="telemetry-metric-value">{format_ms(@summary.median_ms)}</span>
        </div>
        <div class="telemetry-metric-card">
          <span class="telemetry-metric-label">p50</span>
          <span class="telemetry-metric-value">{format_ms(@summary.p50_ms)}</span>
        </div>
        <div class="telemetry-metric-card">
          <span class="telemetry-metric-label">p90</span>
          <span class="telemetry-metric-value">{format_ms(@summary.p90_ms)}</span>
        </div>
        <div class="telemetry-metric-card">
          <span class="telemetry-metric-label">p95</span>
          <span class="telemetry-metric-value">{format_ms(@summary.p95_ms)}</span>
        </div>
        <div class="telemetry-metric-card">
          <span class="telemetry-metric-label">error_rate</span>
          <span class={error_rate_class(@summary.error_rate)}>
            {format_rate(@summary.error_rate)}
          </span>
        </div>
      </div>

      <%!-- commands table --%>
      <div class="section">
        <%= if @commands == [] do %>
          <div class="empty-state">No command data for the selected window.</div>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>command</th>
                <th>completed</th>
                <th>ongoing</th>
                <th>error_rate</th>
                <th>mean</th>
                <th>median</th>
                <th>p50</th>
                <th>p90</th>
                <th>p95</th>
                <th>last_seen</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={cmd <- @commands}>
                <td title={cmd.command} class="command-cell">
                  <code>{truncate_command(cmd.command)}</code>
                </td>
                <td>{cmd.completed_count}</td>
                <td>{cmd.ongoing_count}</td>
                <td>
                  <span class={error_rate_class(cmd.error_rate)}>
                    {format_rate(cmd.error_rate)}
                  </span>
                </td>
                <td>{format_ms(cmd.mean_ms)}</td>
                <td>{format_ms(cmd.median_ms)}</td>
                <td>{format_ms(cmd.p50_ms)}</td>
                <td>{format_ms(cmd.p90_ms)}</td>
                <td>{format_ms(cmd.p95_ms)}</td>
                <td>{relative_time(cmd.last_seen_at)}</td>
              </tr>
            </tbody>
          </table>
        <% end %>
      </div>
    </div>
    """
  end
end
