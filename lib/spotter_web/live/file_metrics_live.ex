defmodule SpotterWeb.FileMetricsLive do
  use Phoenix.LiveView

  alias Spotter.Services.FileMetrics
  alias Spotter.Transcripts.{CoChangeGroupCommit, CoChangeGroupMemberStat, Commit, Project}
  alias Spotter.Transcripts.Jobs.IngestRecentCommits

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

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
       selected_project_id: nil,
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
    project_id = parse_project_id(params["project_id"])

    socket =
      socket
      |> assign(selected_project_id: project_id)
      |> load_all_sections()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = parse_project_id(raw_id)
    path = if project_id, do: "/file-metrics?project_id=#{project_id}", else: "/file-metrics"
    {:noreply, push_patch(socket, to: path)}
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
          Tracer.set_status(:error, "enqueue_error: #{inspect(reason)}")
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

  defp load_all_sections(socket) do
    socket
    |> load_heatmap()
    |> load_hotspots()
    |> load_co_change()
    |> load_file_sizes()
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

  defp format_group(group) do
    members = Enum.join(group.members, " + ")
    "#{members} \u00d7#{group.frequency_30d}"
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
      </div>

      <%!-- Section 1: Heat map --%>
      <div class="section" data-testid="heatmap-section">
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

      <%!-- Section 2: Hotspots --%>
      <div class="section" data-testid="hotspots-section">
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
          <div class="hotspot-list">
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

              <div class="hotspot-meta">
                <span>Lines {entry.line_start}-{entry.line_end}</span>
                <span>Analyzed {relative_time(entry.analyzed_at)}</span>
                <span class="model-tag">{entry.model_used}</span>
                <span :if={strategy_label(entry.metadata)} class="model-tag">
                  {strategy_label(entry.metadata)}
                </span>
              </div>

              <details class="snippet-details">
                <summary>Preview snippet</summary>
                <pre class="snippet-pre"><code>{entry.snippet}</code></pre>
              </details>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Section 3: Co-change --%>
      <div class="section" data-testid="co-change-section">
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
                      Max Co-Change (30d){cc_sort_indicator(assigns, :max_frequency_30d)}
                    </button>
                  </th>
                  <th>
                    <button phx-click="cc_sort" phx-value-field="last_seen_at" class="sort-btn">
                      Last Seen{cc_sort_indicator(assigns, :last_seen_at)}
                    </button>
                  </th>
                  <th>Co-change groups</th>
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
                      <span :for={group <- row.groups} class="badge" style="margin-right: 0.5rem;">
                        {format_group(group)}
                      </span>
                    </td>
                  </tr>
                  <%= if @cc_expanded_member == row.member do %>
                    <tr class="detail-row">
                      <td colspan="4">
                        <div class="detail-panel" style="padding: 1rem;">
                          <%= for group <- row.groups do %>
                            <div style="margin-bottom: 1.5rem;">
                              <h4 style="margin: 0 0 0.5rem 0;">{format_group(group)}</h4>

                              <div style="margin-bottom: 0.75rem;">
                                <strong>Members</strong>
                                <% stats = Map.get(@cc_member_stats, group.group_key, []) %>
                                <%= if stats == [] do %>
                                  <div class="empty-state-small" style="padding: 0.25rem 0; opacity: 0.6;">No file metrics available.</div>
                                <% else %>
                                  <table class="inner-table" style="margin-top: 0.25rem;">
                                    <thead>
                                      <tr>
                                        <th>Path</th>
                                        <th>Size</th>
                                        <th>LOC</th>
                                        <th>Measured at</th>
                                      </tr>
                                    </thead>
                                    <tbody>
                                      <tr :for={stat <- stats}>
                                        <td>{stat.member_path}</td>
                                        <td>{format_bytes(stat.size_bytes)}</td>
                                        <td>{stat.loc || "-"}</td>
                                        <td>{format_datetime(stat.measured_at)}</td>
                                      </tr>
                                    </tbody>
                                  </table>
                                <% end %>
                              </div>

                              <div>
                                <strong>Relevant Commits</strong>
                                <% commits = Map.get(@cc_group_commits, group.group_key, []) %>
                                <%= if commits == [] do %>
                                  <div class="empty-state-small" style="padding: 0.25rem 0; opacity: 0.6;">No commit provenance recorded.</div>
                                <% else %>
                                  <div style="margin-top: 0.25rem;">
                                    <%= for gc <- commits do %>
                                      <div style="margin-bottom: 0.5rem;">
                                        <button
                                          phx-click="cc_toggle_commit_detail"
                                          phx-value-hash={gc.commit_hash}
                                          class="commit-link-btn"
                                          aria-expanded={to_string(@cc_expanded_commit_hash == gc.commit_hash)}
                                          aria-label={"Show details for commit #{String.slice(gc.commit_hash, 0, 8)}"}
                                        >
                                          <code>{String.slice(gc.commit_hash, 0, 8)}</code>
                                        </button>
                                        <span style="opacity: 0.6; margin-left: 0.5rem;">{format_datetime(gc.committed_at)}</span>

                                        <%= if @cc_expanded_commit_hash == gc.commit_hash do %>
                                          <% detail = Map.get(@cc_commit_details, gc.commit_hash) %>
                                          <div class="commit-detail-panel" style="margin: 0.5rem 0 0 1rem; padding: 0.5rem; border-left: 2px solid var(--border-color, #444);">
                                            <%= if detail do %>
                                              <div><strong>Hash:</strong> <code>{detail.commit_hash}</code></div>
                                              <div><strong>Date:</strong> {format_datetime(detail.committed_at)}</div>
                                              <div :if={detail.git_branch}><strong>Branch:</strong> {detail.git_branch}</div>
                                              <div :if={detail.changed_files != []}>
                                                <strong>Changed files ({length(detail.changed_files)}):</strong>
                                                <ul style="margin: 0.25rem 0 0 1rem; padding: 0;">
                                                  <li :for={f <- detail.changed_files} style="font-size: 0.85em;">{f}</li>
                                                </ul>
                                              </div>
                                            <% else %>
                                              <div style="opacity: 0.6;">Commit details not available in database.</div>
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

      <%!-- Section 4: File size --%>
      <div class="section" data-testid="file-size-section">
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
      .section { margin-top: 2rem; }
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
