defmodule SpotterWeb.FileMetricsLive do
  use Phoenix.LiveView

  alias Spotter.Observability.ErrorReport
  alias Spotter.Services.{FileDetail, FileMetrics}
  alias Spotter.Transcripts.{CoChangeGroupCommit, CoChangeGroupMemberStat, Commit, Project}
  alias Spotter.Transcripts.Jobs.IngestRecentCommits

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  @valid_tabs ~w(heatmap hotspots co-change file-size)
  @tab_atoms %{
    "heatmap" => :heatmap,
    "hotspots" => :hotspots,
    "co-change" => :co_change,
    "file-size" => :file_size
  }

  @impl true
  def mount(_params, _session, socket) do
    projects =
      try do
        Project |> Ash.read!()
      rescue
        _ -> []
      end

    {:ok,
     assign(socket,
       projects: projects,
       selected_project_id: first_project_id(projects),
       active_tab: :heatmap,
       # Heat map state
       hm_min_score: 0,
       hm_sort_by: :heat_score,
       heatmap_entries: [],
       # Hotspots state
       hs_min_score: 0,
       hs_sort_by: :overall_score,
       hotspot_entries: [],
       # Co-change state
       cc_scope: :file,
       cc_sort_by: :max_frequency_30d,
       cc_sort_dir: :desc,
       cc_rows: [],
       cc_expanded_member: nil,
       cc_expanded_commit_hash: nil,
       cc_member_stats: %{},
       cc_group_commits: %{},
       cc_commit_details: %{},
       # File size state
       fs_sort_by: :size_bytes,
       file_size_rows: []
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id =
      normalize_project_id(socket.assigns.projects, parse_project_id(params["project_id"]))

    tab = parse_tab(params["tab"])

    socket =
      socket
      |> assign(selected_project_id: project_id, active_tab: tab)
      |> load_active_tab()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = normalize_project_id(socket.assigns.projects, parse_project_id(raw_id))
    {:noreply, push_patch(socket, to: tab_path(project_id, socket.assigns.active_tab))}
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply,
     push_patch(socket, to: tab_path(socket.assigns.selected_project_id, parse_tab(tab)))}
  end

  # Heat map events
  def handle_event("hm_filter_min_score", %{"min_score" => raw}, socket) do
    min_score = parse_min_score(raw)

    {:noreply,
     socket
     |> assign(hm_min_score: min_score)
     |> load_heatmap()}
  end

  def handle_event("hm_sort_by", %{"field" => field}, socket) do
    sort_by = if field == "change_count_30d", do: :change_count_30d, else: :heat_score

    {:noreply,
     socket
     |> assign(hm_sort_by: sort_by)
     |> load_heatmap()}
  end

  # Hotspots events
  def handle_event("hs_filter_min_score", %{"min_score" => raw}, socket) do
    min_score = parse_min_score(raw)

    {:noreply,
     socket
     |> assign(hs_min_score: min_score)
     |> load_hotspots()}
  end

  def handle_event("hs_sort_by", %{"field" => field}, socket) do
    sort_by = if field == "analyzed_at", do: :analyzed_at, else: :overall_score

    {:noreply,
     socket
     |> assign(hs_sort_by: sort_by)
     |> load_hotspots()}
  end

  def handle_event("analyze_commits", _params, %{assigns: %{selected_project_id: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Select a project first.")}
  end

  def handle_event("analyze_commits", _params, socket) do
    project_id = socket.assigns.selected_project_id

    Tracer.with_span "spotter.file_metrics_live.analyze_commits" do
      Tracer.set_attribute("spotter.project_id", project_id)

      case %{project_id: project_id, limit: 10}
           |> IngestRecentCommits.new()
           |> Oban.insert() do
        {:ok, _job} ->
          {:noreply,
           put_flash(socket, :info, "Commit analysis queued (up to 10 recent commits).")}

        {:error, reason} ->
          ErrorReport.set_trace_error(
            "enqueue_error",
            "enqueue_error: #{inspect(reason)}",
            "live.file_metrics_live"
          )

          {:noreply, put_flash(socket, :error, "Failed to queue commit analysis.")}
      end
    end
  end

  # Co-change events
  def handle_event("cc_toggle_scope", %{"scope" => scope}, socket) do
    scope = if scope == "directory", do: :directory, else: :file

    {:noreply,
     socket
     |> assign(
       cc_scope: scope,
       cc_expanded_member: nil,
       cc_expanded_commit_hash: nil
     )
     |> load_co_change()}
  end

  def handle_event("cc_sort", %{"field" => field}, socket) do
    field = String.to_existing_atom(field)
    %{cc_sort_by: current_field, cc_sort_dir: current_dir} = socket.assigns

    new_dir =
      if field == current_field do
        if current_dir == :asc, do: :desc, else: :asc
      else
        :desc
      end

    {:noreply,
     socket
     |> assign(cc_sort_by: field, cc_sort_dir: new_dir)
     |> sort_cc_rows()}
  end

  def handle_event("cc_toggle_expand", %{"member" => member}, socket) do
    new_expanded =
      if socket.assigns.cc_expanded_member == member, do: nil, else: member

    socket =
      socket
      |> assign(cc_expanded_member: new_expanded, cc_expanded_commit_hash: nil)
      |> maybe_load_provenance(new_expanded)

    {:noreply, socket}
  end

  def handle_event("cc_toggle_commit_detail", %{"hash" => hash}, socket) do
    new_hash =
      if socket.assigns.cc_expanded_commit_hash == hash, do: nil, else: hash

    socket =
      if new_hash && not Map.has_key?(socket.assigns.cc_commit_details, new_hash) do
        load_commit_detail(socket, new_hash)
      else
        socket
      end

    {:noreply, assign(socket, cc_expanded_commit_hash: new_hash)}
  end

  # File size events
  def handle_event("fs_sort_by", %{"field" => field}, socket) do
    sort_by = if field == "loc", do: :loc, else: :size_bytes

    {:noreply,
     socket
     |> assign(fs_sort_by: sort_by)
     |> load_file_sizes()}
  end

  # --- Data loading ---

  defp parse_tab(tab) when tab in @valid_tabs, do: Map.fetch!(@tab_atoms, tab)
  defp parse_tab(_), do: :heatmap

  defp tab_to_param(:heatmap), do: "heatmap"
  defp tab_to_param(:hotspots), do: "hotspots"
  defp tab_to_param(:co_change), do: "co-change"
  defp tab_to_param(:file_size), do: "file-size"

  defp tab_path(project_id, tab) do
    base = if project_id, do: "/projects/#{project_id}/file-metrics", else: "/file-metrics"
    param = tab_to_param(tab)
    if param == "heatmap", do: base, else: "#{base}?tab=#{param}"
  end

  defp load_active_tab(socket) do
    case socket.assigns.active_tab do
      :heatmap -> load_heatmap(socket)
      :hotspots -> load_hotspots(socket)
      :co_change -> load_co_change(socket)
      :file_size -> load_file_sizes(socket)
    end
  end

  defp load_heatmap(socket) do
    %{selected_project_id: pid, hm_min_score: min, hm_sort_by: sort} = socket.assigns
    assign(socket, heatmap_entries: FileMetrics.list_heatmap(pid, min, sort))
  end

  defp load_hotspots(socket) do
    %{selected_project_id: pid, hs_min_score: min, hs_sort_by: sort} = socket.assigns
    assign(socket, hotspot_entries: FileMetrics.list_hotspots(pid, min, sort))
  end

  defp load_co_change(socket) do
    %{selected_project_id: pid, cc_scope: scope} = socket.assigns

    rows = FileMetrics.list_co_change_rows(pid, scope)

    socket
    |> assign(
      cc_rows: rows,
      cc_member_stats: %{},
      cc_group_commits: %{}
    )
    |> sort_cc_rows()
  end

  defp load_file_sizes(socket) do
    %{selected_project_id: pid, fs_sort_by: sort_by} = socket.assigns

    rows = FileMetrics.list_file_sizes(pid)

    sorted =
      case sort_by do
        :loc ->
          Enum.sort_by(rows, fn r -> {-(r.loc || 0), -(r.size_bytes || 0), r.member_path} end)

        _ ->
          rows
      end

    assign(socket, file_size_rows: sorted)
  end

  defp sort_cc_rows(socket) do
    %{cc_rows: rows, cc_sort_by: field, cc_sort_dir: dir} = socket.assigns

    sorted =
      case {field, dir} do
        {:member, :asc} ->
          Enum.sort_by(rows, & &1.member)

        {:member, :desc} ->
          Enum.sort_by(rows, & &1.member, :desc)

        {:max_frequency_30d, :desc} ->
          Enum.sort_by(rows, fn r -> {-r.max_frequency_30d, r.member} end)

        {:max_frequency_30d, :asc} ->
          Enum.sort_by(rows, fn r -> {r.max_frequency_30d, r.member} end)

        {:last_seen_at, :desc} ->
          Enum.sort_by(
            rows,
            fn r -> r.last_seen_at || ~U[1970-01-01 00:00:00Z] end,
            {:desc, DateTime}
          )

        {:last_seen_at, :asc} ->
          Enum.sort_by(
            rows,
            fn r -> r.last_seen_at || ~U[1970-01-01 00:00:00Z] end,
            {:asc, DateTime}
          )
      end

    assign(socket, cc_rows: sorted)
  end

  defp maybe_load_provenance(socket, nil), do: socket

  defp maybe_load_provenance(socket, member) do
    %{selected_project_id: project_id, cc_scope: scope} = socket.assigns

    stats =
      try do
        CoChangeGroupMemberStat
        |> Ash.Query.filter(
          project_id == ^project_id and scope == ^scope and member_path == ^member
        )
        |> Ash.read!()
      rescue
        _ -> []
      end

    group_keys =
      socket.assigns.cc_rows
      |> Enum.find(fn r -> r.member == member end)
      |> case do
        nil -> []
        row -> Enum.map(row.groups, & &1.group_key)
      end

    commits_by_group =
      Enum.reduce(group_keys, %{}, fn gk, acc ->
        commits =
          try do
            CoChangeGroupCommit
            |> Ash.Query.filter(
              project_id == ^project_id and scope == ^scope and group_key == ^gk
            )
            |> Ash.read!()
            |> Enum.sort_by(& &1.committed_at, {:desc, DateTime})
            |> Enum.take(10)
          rescue
            _ -> []
          end

        Map.put(acc, gk, commits)
      end)

    stats_by_group = Enum.group_by(stats, & &1.group_key)

    socket
    |> assign(
      cc_member_stats: Map.merge(socket.assigns.cc_member_stats, stats_by_group),
      cc_group_commits: Map.merge(socket.assigns.cc_group_commits, commits_by_group)
    )
  end

  defp load_commit_detail(socket, hash) do
    detail =
      try do
        Commit
        |> Ash.Query.filter(commit_hash == ^hash)
        |> Ash.read!()
        |> List.first()
      rescue
        _ -> nil
      end

    assign(socket, cc_commit_details: Map.put(socket.assigns.cc_commit_details, hash, detail))
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

  defp parse_min_score(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, _} -> max(0, min(n, 100))
      :error -> 0
    end
  end

  defp parse_min_score(_), do: 0

  defp heat_badge_class(score) when score >= 70, do: "badge badge-hot"
  defp heat_badge_class(score) when score >= 40, do: "badge badge-warm"
  defp heat_badge_class(score) when score >= 15, do: "badge badge-mild"
  defp heat_badge_class(_), do: "badge badge-cold"

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
    name |> String.replace("_", " ") |> String.capitalize()
  end

  defp snippet_language(relative_path), do: FileDetail.language_class(relative_path)

  defp snippet_line_numbers(line_start, line_end)
       when is_integer(line_start) and is_integer(line_end) do
    line_start..line_end |> Enum.map_join("\n", &to_string/1)
  end

  defp snippet_line_numbers(_, _), do: ""

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

  defp short_hash(nil), do: "???????"
  defp short_hash(commit), do: String.slice(commit.commit_hash, 0, 7)

  defp commit_subject(nil), do: ""
  defp commit_subject(commit), do: commit.subject || ""

  defp selected_project(assigns) do
    Enum.find(assigns.projects, &(&1.id == assigns.selected_project_id))
  end

  defp strategy_label(metadata) when is_map(metadata) do
    case Map.get(metadata, "strategy") do
      "single_run" -> "single pass"
      "explore_then_chunked" -> "explore + chunked"
      other -> other
    end
  end

  defp strategy_label(_), do: nil

  defp format_group_title(group) do
    Enum.map_join(group.members, " + ", &Path.basename/1)
  end

  defp format_group_count(groups) do
    count = length(groups)
    if count == 1, do: "1 group", else: "#{count} groups"
  end

  defp member_meta_text(stat) do
    parts =
      [
        if(stat.size_bytes, do: format_bytes(stat.size_bytes)),
        if(stat.loc, do: "#{stat.loc} LOC")
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(parts, " \u00b7 ")
  end

  defp scope_label(:file), do: "File"
  defp scope_label(:directory), do: "Directory"

  defp cc_sort_indicator(assigns, field) do
    if assigns.cc_sort_by == field do
      if assigns.cc_sort_dir == :asc, do: " \u2191", else: " \u2193"
    else
      ""
    end
  end

  defp format_datetime(nil), do: "-"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp format_bytes(nil), do: "-"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp file_link(project_id, path) do
    if project_id do
      "/projects/#{project_id}/files/#{path}"
    end
  end

  defp has_score_components?(metadata) when is_map(metadata) do
    case metadata do
      %{"metrics" => m} when is_map(m) -> true
      %{metrics: m} when is_map(m) -> true
      _ -> false
    end
  end

  defp has_score_components?(_), do: false

  defp get_metrics(metadata) do
    case metadata do
      %{"metrics" => m} when is_map(m) -> m
      %{metrics: m} when is_map(m) -> m
      _ -> %{}
    end
  end

  defp format_metric(metadata, key) do
    metrics = get_metrics(metadata)

    case Map.get(metrics, key) || Map.get(metrics, String.to_existing_atom(key)) do
      nil -> "N/A"
      val when is_number(val) -> "#{Float.round(val * 1.0, 1)}"
      _ -> "N/A"
    end
  rescue
    _ -> "N/A"
  end

  defp blast_confidence(metadata) do
    metrics = get_metrics(metadata)

    case Map.get(metrics, "blast_radius_confidence") ||
           Map.get(metrics, :blast_radius_confidence) do
      val when val in ["high", "medium", "low"] -> val
      _ -> "unknown"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="page-header">
        <h1>File metrics</h1>
      </div>

      <%!-- Shared project filter --%>
      <div class="filter-section">
        <div>
          <label class="filter-label">Project</label>
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

      <%!-- Tab bar --%>
      <div class="tab-bar" role="tablist">
        <button
          :for={{tab, label} <- [{:heatmap, "Heat map"}, {:hotspots, "Hotspots"}, {:co_change, "Co-change"}, {:file_size, "File size"}]}
          phx-click="select_tab"
          phx-value-tab={tab_to_param(tab)}
          role="tab"
          aria-current={if @active_tab == tab, do: "page"}
          class={"tab-btn#{if @active_tab == tab, do: " is-active"}"}
        >
          {label}
        </button>
      </div>

      <%!-- Heat map tab --%>
      <div :if={@active_tab == :heatmap} class="section" data-testid="heatmap-section">
        <h2 class="section-heading">Heat map</h2>

        <div class="filter-section">
          <div>
            <label class="filter-label">Min score</label>
            <div class="filter-bar">
              <button
                :for={threshold <- [0, 15, 40, 70]}
                phx-click="hm_filter_min_score"
                phx-value-min_score={threshold}
                class={"filter-btn#{if @hm_min_score == threshold, do: " is-active"}"}
              >
                {threshold}+
              </button>
            </div>
          </div>
          <div>
            <label class="filter-label">Sort by</label>
            <div class="filter-bar">
              <button
                phx-click="hm_sort_by"
                phx-value-field="heat_score"
                class={"filter-btn#{if @hm_sort_by == :heat_score, do: " is-active"}"}
              >
                Heat score
              </button>
              <button
                phx-click="hm_sort_by"
                phx-value-field="change_count_30d"
                class={"filter-btn#{if @hm_sort_by == :change_count_30d, do: " is-active"}"}
              >
                Change count
              </button>
            </div>
          </div>
        </div>

        <%= if @heatmap_entries == [] do %>
          <div class="empty-state">No file activity data yet.</div>
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
                  <a
                    :if={entry.project_id}
                    href={"/projects/#{entry.project_id}/files/#{entry.relative_path}"}
                    class="file-link"
                  >
                    {entry.relative_path}
                  </a>
                  <span :if={!entry.project_id}>{entry.relative_path}</span>
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

      <%!-- Hotspots tab --%>
      <div :if={@active_tab == :hotspots} class="section" data-testid="hotspots-section">
        <div class="section-header">
          <h2 class="section-heading">Hotspots</h2>
          <button :if={@selected_project_id} phx-click="analyze_commits" class="btn">
            Analyze recent commits
          </button>
        </div>

        <div class="filter-section">
          <div>
            <label class="filter-label">Min score</label>
            <div class="filter-bar">
              <button
                :for={threshold <- [0, 15, 40, 70]}
                phx-click="hs_filter_min_score"
                phx-value-min_score={threshold}
                class={"filter-btn#{if @hs_min_score == threshold, do: " is-active"}"}
              >
                {threshold}+
              </button>
            </div>
          </div>
          <div>
            <label class="filter-label">Sort by</label>
            <div class="filter-bar">
              <button
                phx-click="hs_sort_by"
                phx-value-field="overall_score"
                class={"filter-btn#{if @hs_sort_by == :overall_score, do: " is-active"}"}
              >
                Score
              </button>
              <button
                phx-click="hs_sort_by"
                phx-value-field="analyzed_at"
                class={"filter-btn#{if @hs_sort_by == :analyzed_at, do: " is-active"}"}
              >
                Analyzed at
              </button>
            </div>
          </div>
        </div>

        <%= if @hotspot_entries == [] do %>
          <div class="empty-state">
            <%= if @selected_project_id && selected_project(assigns) do %>
              No commit hotspots for {selected_project(assigns).name} yet.
            <% else %>
              No commit hotspots yet.
            <% end %>
            Select a project and click "Analyze recent commits" to get started.
          </div>
        <% else %>
          <div class="hotspot-list" id="hotspot-list" phx-hook="SnippetHighlighter">
            <div :for={%{hotspot: entry, commit: commit} <- @hotspot_entries} class="hotspot-card">
              <div class="hotspot-header">
                <div class="hotspot-path-group">
                  <a
                    :if={entry.project_id}
                    href={"/projects/#{entry.project_id}/files/#{entry.relative_path}"}
                    class="hotspot-path"
                    title={entry.relative_path}
                  >
                    {entry.relative_path}
                  </a>
                  <span :if={!entry.project_id} class="hotspot-path" title={entry.relative_path}>
                    {entry.relative_path}
                  </span>
                  <span :if={entry.symbol_name} class="symbol-name">{entry.symbol_name}</span>
                </div>
                <span class={score_badge_class(entry.overall_score)}>
                  {Float.round(entry.overall_score, 1)}
                </span>
              </div>

              <div class="commit-info">
                <code class="commit-hash">{short_hash(commit)}</code>
                <span class="commit-subject">{commit_subject(commit)}</span>
              </div>

              <div :if={entry.reason} class="hotspot-reason">{entry.reason}</div>

              <div class="hotspot-snippet">
                <pre><span class="snippet-line-numbers">{snippet_line_numbers(entry.line_start, entry.line_end)}</span><code class={"language-#{snippet_language(entry.relative_path)}"}>{entry.snippet}</code></pre>
              </div>

              <details class="rubric-details">
                <summary>Scoring breakdown</summary>
                <div class="rubric-factors">
                  <div :for={{name, score} <- entry.rubric || %{}} class="rubric-row">
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

                <div
                  :if={has_score_components?(entry.metadata)}
                  class="score-components"
                  data-testid="score-components"
                >
                  <h4 class="score-components-heading">Score Components</h4>
                  <div class="score-components-grid">
                    <div class="score-component">
                      <span class="score-component-label">Complexity</span>
                      <span class="score-component-value">
                        {format_metric(entry.metadata, "complexity_score")}
                      </span>
                    </div>
                    <div class="score-component">
                      <span class="score-component-label">Churn</span>
                      <span class="score-component-value">
                        {format_metric(entry.metadata, "change_churn_score")}
                      </span>
                    </div>
                    <div class="score-component">
                      <span class="score-component-label">Blast radius</span>
                      <span class="score-component-value">
                        {format_metric(entry.metadata, "blast_radius_score")}
                      </span>
                    </div>
                    <div class="score-component">
                      <span class="score-component-label">Test exposure</span>
                      <span class="score-component-value">
                        {format_metric(entry.metadata, "test_exposure_score")}
                      </span>
                    </div>
                    <div class="score-component">
                      <span class="score-component-label">Confidence</span>
                      <span class={"confidence-badge confidence-#{blast_confidence(entry.metadata)}"}>
                        {blast_confidence(entry.metadata)}
                      </span>
                    </div>
                  </div>
                </div>
              </details>

              <div class="hotspot-meta">
                <span>Lines {entry.line_start}-{entry.line_end}</span>
                <span>Analyzed {relative_time(entry.analyzed_at)}</span>
                <span class="model-tag">{entry.model_used}</span>
                <span :if={strategy_label(entry.metadata)} class="model-tag">
                  {strategy_label(entry.metadata)}
                </span>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Co-change tab --%>
      <div :if={@active_tab == :co_change} class="section" data-testid="co-change-section">
        <h2 class="section-heading">Co-change</h2>

        <div class="filter-section">
          <div>
            <label class="filter-label">Scope</label>
            <div class="filter-bar">
              <button
                phx-click="cc_toggle_scope"
                phx-value-scope="file"
                class={"filter-btn#{if @cc_scope == :file, do: " is-active"}"}
              >
                Files
              </button>
              <button
                phx-click="cc_toggle_scope"
                phx-value-scope="directory"
                class={"filter-btn#{if @cc_scope == :directory, do: " is-active"}"}
              >
                Directories
              </button>
            </div>
          </div>
        </div>

        <%= if @selected_project_id == nil do %>
          <div class="empty-state">Select a project to view co-change groups.</div>
        <% else %>
          <%= if @cc_rows == [] do %>
            <div class="empty-state">
              <%= if selected_project(assigns) do %>
                No co-change groups for {selected_project(assigns).name} yet.
              <% else %>
                Project not found.
              <% end %>
            </div>
          <% else %>
            <table>
              <thead>
                <tr>
                  <th>
                    <button phx-click="cc_sort" phx-value-field="member" class="sort-btn">
                      {scope_label(@cc_scope)}{cc_sort_indicator(assigns, :member)}
                    </button>
                  </th>
                  <th>
                    <button phx-click="cc_sort" phx-value-field="max_frequency_30d" class="sort-btn">
                      Max Freq (30d){cc_sort_indicator(assigns, :max_frequency_30d)}
                    </button>
                  </th>
                  <th>
                    <button phx-click="cc_sort" phx-value-field="last_seen_at" class="sort-btn">
                      Last Seen{cc_sort_indicator(assigns, :last_seen_at)}
                    </button>
                  </th>
                  <th>Groups</th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @cc_rows do %>
                  <tr>
                    <td title={row.member}>
                      <button
                        phx-click="cc_toggle_expand"
                        phx-value-member={row.member}
                        class="expand-btn"
                        aria-expanded={to_string(@cc_expanded_member == row.member)}
                        aria-label={"Expand details for #{row.member}"}
                      >
                        <span class="expand-icon">{if @cc_expanded_member == row.member, do: "\u25BE", else: "\u25B8"}</span>
                        <%= if @selected_project_id && @cc_scope == :file do %>
                          <a href={"/projects/#{@selected_project_id}/files/#{row.member}"} class="file-link">{row.member}</a>
                        <% else %>
                          {row.member}
                        <% end %>
                      </button>
                    </td>
                    <td>{row.max_frequency_30d}</td>
                    <td>{format_datetime(row.last_seen_at)}</td>
                    <td>
                      <span class="cochange-group-count">{format_group_count(row.groups)}</span>
                    </td>
                  </tr>
                  <%= if @cc_expanded_member == row.member do %>
                    <tr class="detail-row">
                      <td colspan="4">
                        <div class="cochange-detail-panel">
                          <%= for group <- row.groups do %>
                            <div class="cochange-group-card">
                              <div class="cochange-group-header">
                                <span class="cochange-group-title">{format_group_title(group)}</span>
                                <span class="cochange-frequency-badge">&times;{group.frequency_30d}</span>
                              </div>

                              <div class="cochange-section">
                                <span class="cochange-section-label">Members</span>
                                <% stats = Map.get(@cc_member_stats, group.group_key, []) %>
                                <%= if stats == [] do %>
                                  <div class="empty-state-small">No file metrics available.</div>
                                <% else %>
                                  <div class="cochange-member-list">
                                    <div :for={stat <- stats} class="cochange-member-item">
                                      <%= if file_link(@selected_project_id, stat.member_path) do %>
                                        <a href={file_link(@selected_project_id, stat.member_path)} class="cochange-member-path">{stat.member_path}</a>
                                      <% else %>
                                        <span class="cochange-member-path">{stat.member_path}</span>
                                      <% end %>
                                      <span :if={member_meta_text(stat) != ""} class="cochange-member-meta">
                                        {member_meta_text(stat)}
                                      </span>
                                    </div>
                                  </div>
                                <% end %>
                              </div>

                              <div class="cochange-section">
                                <span class="cochange-section-label">Relevant Commits</span>
                                <% commits = Map.get(@cc_group_commits, group.group_key, []) %>
                                <%= if commits == [] do %>
                                  <div class="empty-state-small">No commit provenance recorded.</div>
                                <% else %>
                                  <div class="cochange-commit-list">
                                    <%= for gc <- commits do %>
                                      <div>
                                        <button
                                          phx-click="cc_toggle_commit_detail"
                                          phx-value-hash={gc.commit_hash}
                                          class="commit-link-btn"
                                          aria-expanded={to_string(@cc_expanded_commit_hash == gc.commit_hash)}
                                          aria-label={"Show details for commit #{String.slice(gc.commit_hash, 0, 8)}"}
                                        >
                                          <code>{String.slice(gc.commit_hash, 0, 8)}</code>
                                          <span class="text-muted text-xs">{format_datetime(gc.committed_at)}</span>
                                        </button>

                                        <%= if @cc_expanded_commit_hash == gc.commit_hash do %>
                                          <% detail = Map.get(@cc_commit_details, gc.commit_hash) %>
                                          <div class="commit-detail-inline">
                                            <%= if detail do %>
                                              <div><strong>Hash:</strong> <code>{detail.commit_hash}</code></div>
                                              <div><strong>Date:</strong> {format_datetime(detail.committed_at)}</div>
                                              <div :if={detail.git_branch}><strong>Branch:</strong> {detail.git_branch}</div>
                                              <div :if={detail.changed_files != []}>
                                                <strong>Changed files ({length(detail.changed_files)}):</strong>
                                                <ul class="commit-changed-files">
                                                  <li :for={f <- detail.changed_files}>{f}</li>
                                                </ul>
                                              </div>
                                            <% else %>
                                              <div class="empty-state-small">Commit details not available in database.</div>
                                            <% end %>
                                          </div>
                                        <% end %>
                                      </div>
                                    <% end %>
                                  </div>
                                <% end %>
                              </div>
                            </div>
                          <% end %>
                        </div>
                      </td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          <% end %>
        <% end %>
      </div>

      <%!-- File size tab --%>
      <div :if={@active_tab == :file_size} class="section" data-testid="file-size-section">
        <h2 class="section-heading">File size</h2>

        <div class="filter-section">
          <div>
            <label class="filter-label">Sort by</label>
            <div class="filter-bar">
              <button
                phx-click="fs_sort_by"
                phx-value-field="size_bytes"
                class={"filter-btn#{if @fs_sort_by == :size_bytes, do: " is-active"}"}
              >
                Size
              </button>
              <button
                phx-click="fs_sort_by"
                phx-value-field="loc"
                class={"filter-btn#{if @fs_sort_by == :loc, do: " is-active"}"}
              >
                LOC
              </button>
            </div>
          </div>
        </div>

        <%= if @file_size_rows == [] do %>
          <div class="empty-state">No file size data yet.</div>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>File</th>
                <th>LOC</th>
                <th>Size</th>
                <th>Measured at</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @file_size_rows}>
                <td title={row.member_path}>
                  <%= if file_link(row.project_id, row.member_path) do %>
                    <a href={file_link(row.project_id, row.member_path)} class="file-link">
                      {row.member_path}
                    </a>
                  <% else %>
                    {row.member_path}
                  <% end %>
                </td>
                <td>{row.loc || "-"}</td>
                <td>{format_bytes(row.size_bytes)}</td>
                <td>{format_datetime(row.measured_at)}</td>
              </tr>
            </tbody>
          </table>
        <% end %>
      </div>
    </div>

    <style>
      .tab-bar {
        display: flex;
        gap: 0;
        border-bottom: 1px solid #333;
        margin-top: 1.5rem;
        margin-bottom: 0;
      }
      .tab-btn {
        padding: 0.5rem 1rem;
        background: none;
        border: none;
        border-bottom: 2px solid transparent;
        color: #9ca3af;
        cursor: pointer;
        font-size: 0.9rem;
      }
      .tab-btn:hover { color: #d1d5db; }
      .tab-btn.is-active {
        color: #fff;
        border-bottom-color: #3b82f6;
      }

      .section { margin-top: 1rem; }
      .section-header { display: flex; justify-content: space-between; align-items: center; }

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
        margin-bottom: 0.5rem;
      }
      .hotspot-path-group {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        overflow: hidden;
        max-width: 80%;
      }
      .hotspot-path {
        font-family: monospace;
        font-size: 0.9rem;
        color: #93c5fd;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
      .symbol-name {
        font-family: monospace;
        font-size: 0.8rem;
        color: #a78bfa;
        background: #1f2937;
        padding: 0.1rem 0.4rem;
        border-radius: 4px;
        white-space: nowrap;
      }

      .commit-info {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        margin-bottom: 0.5rem;
        font-size: 0.8rem;
      }
      .commit-hash {
        color: #fbbf24;
        background: #1f2937;
        padding: 0.1rem 0.3rem;
        border-radius: 3px;
        font-size: 0.75rem;
      }
      .commit-subject {
        color: #9ca3af;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .hotspot-reason {
        font-size: 0.8rem;
        color: #d1d5db;
        margin-bottom: 0.5rem;
        line-height: 1.4;
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

      .score-components {
        margin-bottom: 0.75rem;
        padding: 0.5rem 0.75rem;
        background: #111827;
        border-radius: 6px;
        border: 1px solid #1f2937;
      }
      .score-components-heading {
        margin: 0 0 0.4rem 0;
        font-size: 0.75rem;
        color: #6b7280;
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }
      .score-components-grid {
        display: flex;
        flex-wrap: wrap;
        gap: 0.5rem 1.5rem;
      }
      .score-component {
        display: flex;
        align-items: center;
        gap: 0.35rem;
      }
      .score-component-label {
        font-size: 0.8rem;
        color: #9ca3af;
      }
      .score-component-value {
        font-size: 0.8rem;
        font-weight: 600;
        color: #d1d5db;
        font-family: monospace;
      }
      .confidence-badge {
        font-size: 0.7rem;
        padding: 0.1rem 0.4rem;
        border-radius: 4px;
        font-weight: 600;
      }
      .confidence-high { background: #065f46; color: #6ee7b7; }
      .confidence-medium { background: #78350f; color: #fcd34d; }
      .confidence-low { background: #1f2937; color: #9ca3af; }
      .confidence-unknown { background: #1f2937; color: #6b7280; }
    </style>
    """
  end
end
