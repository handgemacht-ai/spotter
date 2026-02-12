defmodule SpotterWeb.HeatmapLive do
  use Phoenix.LiveView

  alias Spotter.Transcripts.{FileHeatmap, Project}
  alias SpotterWeb.IngestProgress

  require Ash.Query

  @max_rows 100

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: IngestProgress.subscribe()

    projects =
      try do
        Project |> Ash.read!()
      rescue
        _ -> []
      end

    {:ok,
     socket
     |> assign(
       projects: projects,
       selected_project_id: nil,
       min_score: 0,
       sort_by: :heat_score,
       heatmap_entries: []
     )
     |> IngestProgress.init_ingest()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = parse_project_id(params["project_id"])

    socket =
      socket
      |> assign(selected_project_id: project_id)
      |> load_heatmap()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = parse_project_id(raw_id)
    path = if project_id, do: "/heatmap?project_id=#{project_id}", else: "/heatmap"

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("filter_min_score", %{"min_score" => raw}, socket) do
    min_score = parse_min_score(raw)

    {:noreply,
     socket
     |> assign(min_score: min_score)
     |> load_heatmap()}
  end

  def handle_event("ingest", _params, socket) do
    socket = IngestProgress.start_ingest(socket)
    {:noreply, socket}
  end

  def handle_event("sort_by", %{"field" => field}, socket) do
    sort_by = parse_sort_by(field)

    {:noreply,
     socket
     |> assign(sort_by: sort_by)
     |> load_heatmap()}
  end

  @impl true
  def handle_info(msg, socket)
      when elem(msg, 0) in [
             :ingest_enqueued,
             :sync_started,
             :sync_progress,
             :sync_completed,
             :sync_error
           ] do
    case IngestProgress.handle_progress(msg, socket) do
      {:ok, socket} ->
        socket =
          if elem(msg, 0) == :sync_completed, do: load_heatmap(socket), else: socket

        {:noreply, socket}

      :ignore ->
        {:noreply, socket}
    end
  end

  defp load_heatmap(socket) do
    %{selected_project_id: project_id, min_score: min_score, sort_by: sort_by} = socket.assigns

    query =
      FileHeatmap
      |> Ash.Query.filter(heat_score >= ^min_score)
      |> Ash.Query.sort([{sort_by, :desc}])
      |> Ash.Query.limit(@max_rows)

    query =
      if project_id do
        Ash.Query.filter(query, project_id == ^project_id)
      else
        query
      end

    entries =
      try do
        Ash.read!(query)
      rescue
        _ -> []
      end

    assign(socket, heatmap_entries: entries)
  end

  defp parse_project_id("all"), do: nil
  defp parse_project_id(nil), do: nil
  defp parse_project_id(""), do: nil
  defp parse_project_id(id), do: id

  defp parse_min_score(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, _} -> max(0, min(n, 100))
      :error -> 0
    end
  end

  defp parse_min_score(_), do: 0

  defp parse_sort_by("change_count_30d"), do: :change_count_30d
  defp parse_sort_by(_), do: :heat_score

  defp heat_badge_class(score) when score >= 70, do: "badge badge-hot"
  defp heat_badge_class(score) when score >= 40, do: "badge badge-warm"
  defp heat_badge_class(score) when score >= 15, do: "badge badge-mild"
  defp heat_badge_class(_), do: "badge badge-cold"

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
        <h1>File heat map</h1>
        <div class="page-header-actions">
          <button class="btn" phx-click="ingest" disabled={@ingest_running}>
            <%= if @ingest_running, do: "Ingesting...", else: "Ingest" %>
          </button>
        </div>
      </div>

      <div :if={@ingest_projects != %{}} class="ingest-progress mb-4">
        <%= if @ingest_running do %>
          <span class="sync-syncing">
            Ingesting {Enum.count(@ingest_projects, fn {_, p} -> p.status in [:completed, :error] end)}/{map_size(@ingest_projects)} projects
          </span>
        <% else %>
          <span class="sync-completed">
            Ingested {Enum.count(@ingest_projects, fn {_, p} -> p.status in [:completed, :error] end)}/{map_size(@ingest_projects)} projects
          </span>
        <% end %>
      </div>

      <div class="filter-section">
        <div>
          <label class="filter-label">Project</label>
          <div class="filter-bar">
            <button
              phx-click="filter_project"
              phx-value-project-id="all"
              class={"filter-btn#{if @selected_project_id == nil, do: " is-active"}"}
            >
              All
            </button>
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

        <div>
          <label class="filter-label">Min score</label>
          <div class="filter-bar">
            <button
              :for={threshold <- [0, 15, 40, 70]}
              phx-click="filter_min_score"
              phx-value-min_score={threshold}
              class={"filter-btn#{if @min_score == threshold, do: " is-active"}"}
            >
              {threshold}+
            </button>
          </div>
        </div>

        <div>
          <label class="filter-label">Sort by</label>
          <div class="filter-bar">
            <button
              phx-click="sort_by"
              phx-value-field="heat_score"
              class={"filter-btn#{if @sort_by == :heat_score, do: " is-active"}"}
            >
              Heat score
            </button>
            <button
              phx-click="sort_by"
              phx-value-field="change_count_30d"
              class={"filter-btn#{if @sort_by == :change_count_30d, do: " is-active"}"}
            >
              Change count
            </button>
          </div>
        </div>
      </div>

      <%= if @heatmap_entries == [] do %>
        <div class="empty-state">
          <p>No file activity data yet.</p>
          <p>Click Ingest to import transcripts and compute this heat map.</p>
        </div>
      <% else %>
        <table>
          <thead>
            <tr>
              <th>File</th>
              <th>Heat</th>
              <th>Changes (30d)</th>
              <th>Last changed</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={entry <- @heatmap_entries}>
              <td title={entry.relative_path}>
                {entry.relative_path}
              </td>
              <td>
                <span class={heat_badge_class(entry.heat_score)}>
                  {Float.round(entry.heat_score, 1)}
                </span>
              </td>
              <td>{entry.change_count_30d} changes</td>
              <td>{relative_time(entry.last_changed_at)}</td>
            </tr>
          </tbody>
        </table>
      <% end %>
    </div>

    <style>
      .badge-hot { background: #dc2626; color: #fff; }
      .badge-warm { background: #ea580c; color: #fff; }
      .badge-mild { background: #ca8a04; color: #fff; }
      .badge-cold { background: #6b7280; color: #fff; }
    </style>
    """
  end
end
