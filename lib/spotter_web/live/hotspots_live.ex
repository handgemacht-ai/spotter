defmodule SpotterWeb.HotspotsLive do
  use Phoenix.LiveView

  alias Spotter.Transcripts.{CodeHotspot, Project}

  require Ash.Query

  @max_rows 100

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    case Ash.get(Project, project_id) do
      {:ok, project} ->
        {:ok,
         socket
         |> assign(project: project, min_score: 0, sort_by: :overall_score)
         |> load_hotspots()}

      _ ->
        {:ok, assign(socket, project: nil, hotspot_entries: [])}
    end
  end

  @impl true
  def handle_event("filter_min_score", %{"min_score" => raw}, socket) do
    min_score = parse_min_score(raw)

    {:noreply,
     socket
     |> assign(min_score: min_score)
     |> load_hotspots()}
  end

  def handle_event("sort_by", %{"field" => field}, socket) do
    sort_by = parse_sort_by(field)

    {:noreply,
     socket
     |> assign(sort_by: sort_by)
     |> load_hotspots()}
  end

  defp load_hotspots(socket) do
    %{project: project, min_score: min_score, sort_by: sort_by} = socket.assigns

    entries =
      CodeHotspot
      |> Ash.Query.filter(project_id == ^project.id and overall_score >= ^min_score)
      |> Ash.Query.sort([{sort_by, :desc}])
      |> Ash.Query.limit(@max_rows)
      |> Ash.read!()

    assign(socket, hotspot_entries: entries)
  end

  defp parse_min_score(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, _} -> max(0, min(n, 100))
      :error -> 0
    end
  end

  defp parse_min_score(_), do: 0

  defp parse_sort_by("complexity"), do: :overall_score
  defp parse_sort_by("scored_at"), do: :scored_at
  defp parse_sort_by(_), do: :overall_score

  defp score_badge_class(score) when score >= 70, do: "badge badge-hot"
  defp score_badge_class(score) when score >= 40, do: "badge badge-warm"
  defp score_badge_class(score) when score >= 15, do: "badge badge-mild"
  defp score_badge_class(_), do: "badge badge-cold"

  defp rubric_bar_width(score) when is_number(score), do: "#{round(score)}%"
  defp rubric_bar_width(_), do: "0%"

  defp rubric_bar_color(score) when score >= 70, do: "#dc2626"
  defp rubric_bar_color(score) when score >= 40, do: "#ea580c"
  defp rubric_bar_color(score) when score >= 15, do: "#ca8a04"
  defp rubric_bar_color(_), do: "#6b7280"

  defp format_rubric_name(name) do
    name
    |> String.replace("_", " ")
    |> String.capitalize()
  end

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
      <%= if @project == nil do %>
        <div class="empty-state">
          <p>Project not found.</p>
          <a href="/" class="btn">Back to dashboard</a>
        </div>
      <% else %>
        <div class="page-header">
          <h1>AI Hotspots &mdash; {@project.name}</h1>
          <div>
            <a href={"/projects/#{@project.id}/heatmap"} class="btn btn-ghost">Heatmap</a>
            <a href="/" class="btn btn-ghost">Back</a>
          </div>
        </div>

        <div class="filter-section">
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
                phx-value-field="overall_score"
                class={"filter-btn#{if @sort_by == :overall_score, do: " is-active"}"}
              >
                Score
              </button>
              <button
                phx-click="sort_by"
                phx-value-field="scored_at"
                class={"filter-btn#{if @sort_by == :scored_at, do: " is-active"}"}
              >
                Scored at
              </button>
            </div>
          </div>
        </div>

        <%= if @hotspot_entries == [] do %>
          <div class="empty-state">
            No AI-scored hotspots yet.
            Run the scoring pipeline to analyze top heatmap files.
          </div>
        <% else %>
          <div class="hotspot-list">
            <div :for={entry <- @hotspot_entries} class="hotspot-card">
              <div class="hotspot-header">
                <span class="hotspot-path" title={entry.relative_path}>
                  {entry.relative_path}
                </span>
                <span class={score_badge_class(entry.overall_score)}>
                  {Float.round(entry.overall_score, 1)}
                </span>
              </div>

              <div class="rubric-factors">
                <div :for={{name, score} <- entry.rubric} class="rubric-row">
                  <span class="rubric-name">{format_rubric_name(name)}</span>
                  <div class="rubric-bar-bg">
                    <div
                      class="rubric-bar-fill"
                      style={"width: #{rubric_bar_width(score)}; background: #{rubric_bar_color(score)}"}
                    >
                    </div>
                  </div>
                  <span class="rubric-value">{round(score)}</span>
                </div>
              </div>

              <div class="hotspot-meta">
                <span>Lines {entry.line_start}-{entry.line_end}</span>
                <span>Scored {relative_time(entry.scored_at)}</span>
                <span class="model-tag">{entry.model_used}</span>
              </div>

              <details class="snippet-details">
                <summary>Preview snippet</summary>
                <pre class="snippet-pre"><code>{entry.snippet}</code></pre>
              </details>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>

    <style>
      .badge-hot { background: #dc2626; color: #fff; }
      .badge-warm { background: #ea580c; color: #fff; }
      .badge-mild { background: #ca8a04; color: #fff; }
      .badge-cold { background: #6b7280; color: #fff; }

      .hotspot-list { display: flex; flex-direction: column; gap: 1rem; }
      .hotspot-card {
        border: 1px solid #333;
        border-radius: 8px;
        padding: 1rem;
        background: #1a1a2e;
      }
      .hotspot-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        margin-bottom: 0.75rem;
      }
      .hotspot-path {
        font-family: monospace;
        font-size: 0.9rem;
        color: #93c5fd;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        max-width: 80%;
      }

      .rubric-factors { display: flex; flex-direction: column; gap: 0.35rem; margin-bottom: 0.75rem; }
      .rubric-row { display: flex; align-items: center; gap: 0.5rem; }
      .rubric-name { width: 120px; font-size: 0.8rem; color: #9ca3af; }
      .rubric-bar-bg {
        flex: 1;
        height: 8px;
        background: #374151;
        border-radius: 4px;
        overflow: hidden;
      }
      .rubric-bar-fill {
        height: 100%;
        border-radius: 4px;
        transition: width 0.3s ease;
      }
      .rubric-value { width: 30px; text-align: right; font-size: 0.8rem; color: #9ca3af; }

      .hotspot-meta {
        display: flex;
        gap: 1rem;
        font-size: 0.75rem;
        color: #6b7280;
        margin-bottom: 0.5rem;
      }
      .model-tag {
        background: #1f2937;
        padding: 0.1rem 0.4rem;
        border-radius: 4px;
        font-family: monospace;
      }

      .snippet-details { margin-top: 0.5rem; }
      .snippet-details summary {
        cursor: pointer;
        font-size: 0.8rem;
        color: #9ca3af;
      }
      .snippet-pre {
        margin-top: 0.5rem;
        padding: 0.75rem;
        background: #0d1117;
        border-radius: 6px;
        overflow-x: auto;
        font-size: 0.8rem;
        max-height: 300px;
      }
    </style>
    """
  end
end
