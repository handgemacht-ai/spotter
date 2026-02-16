defmodule SpotterWeb.HistoryLive do
  use Phoenix.LiveView

  alias Spotter.Services.CommitHistory
  alias Spotter.Services.CommitHistoryDeltaSummary
  alias Spotter.Transcripts.SessionPresenter

  @impl true
  def mount(_params, _session, socket) do
    %{projects: projects, branches: branches, default_branch: default_branch} =
      CommitHistory.list_filter_options()

    {:ok,
     socket
     |> assign(
       projects: projects,
       branches: branches,
       default_branch: default_branch,
       selected_project_id: first_project_id(projects),
       selected_branch: default_branch,
       rows: [],
       next_cursor: nil,
       has_more: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id =
      normalize_project_id(socket.assigns.projects, parse_project_id(params["project_id"]))

    branch =
      if Map.has_key?(params, "branch") do
        parse_branch(params["branch"], socket.assigns.branches)
      else
        socket.assigns.default_branch
      end

    socket =
      socket
      |> assign(selected_project_id: project_id, selected_branch: branch)
      |> load_page()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = normalize_project_id(socket.assigns.projects, parse_project_id(raw_id))

    {:noreply,
     push_patch(socket,
       to: build_path(project_id, socket.assigns.selected_branch)
     )}
  end

  def handle_event("filter_branch", %{"branch" => raw_branch}, socket) do
    branch = parse_branch(raw_branch, socket.assigns.branches)

    {:noreply,
     push_patch(socket,
       to: build_path(socket.assigns.selected_project_id, branch)
     )}
  end

  def handle_event("load_more", _params, socket) do
    cursor = socket.assigns.next_cursor

    if cursor do
      filters = build_filters(socket.assigns)

      result = CommitHistory.list_commits_with_sessions(filters, %{after: cursor})
      rows = enrich_with_delta_summaries(result.rows, socket.assigns.selected_project_id)

      {:noreply,
       assign(socket,
         rows: socket.assigns.rows ++ rows,
         next_cursor: result.cursor,
         has_more: result.has_more
       )}
    else
      {:noreply, socket}
    end
  end

  defp load_page(socket) do
    filters = build_filters(socket.assigns)

    result =
      try do
        CommitHistory.list_commits_with_sessions(filters)
      rescue
        _ -> %{rows: [], has_more: false, cursor: nil}
      end

    rows = enrich_with_delta_summaries(result.rows, socket.assigns.selected_project_id)

    assign(socket,
      rows: rows,
      next_cursor: result.cursor,
      has_more: result.has_more
    )
  end

  defp enrich_with_delta_summaries([], _project_id), do: []
  defp enrich_with_delta_summaries(rows, nil), do: rows

  defp enrich_with_delta_summaries(rows, project_id) do
    summaries =
      try do
        CommitHistoryDeltaSummary.summaries_for_commits(project_id, rows)
      rescue
        _ -> %{}
      end

    Enum.map(rows, fn row ->
      Map.put(row, :delta_summary, Map.get(summaries, row.commit.id))
    end)
  end

  defp build_filters(assigns) do
    %{}
    |> maybe_put(:project_id, assigns.selected_project_id)
    |> maybe_put(:branch, assigns.selected_branch)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp build_path(project_id, branch) do
    params = %{branch: branch || "all"}
    params = if project_id, do: Map.put(params, :project_id, project_id), else: params

    "/history?#{URI.encode_query(params)}"
  end

  defp parse_project_id("all"), do: nil
  defp parse_project_id(nil), do: nil
  defp parse_project_id(""), do: nil
  defp parse_project_id(id), do: id

  defp first_project_id(projects), do: List.first(projects) |> then(&(&1 && &1.id))

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

  defp parse_branch(nil, _valid), do: nil
  defp parse_branch("", _valid), do: nil
  defp parse_branch("all", _valid), do: nil
  defp parse_branch(branch, valid) when is_list(valid), do: if(branch in valid, do: branch)

  defp format_timestamp(nil), do: "\u2014"

  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  @conventional_commit_emojis %{
    "feat" => "\u2728",
    "fix" => "\U0001F41B",
    "chore" => "\U0001F9F9",
    "docs" => "\U0001F4DD",
    "refactor" => "\u267B\uFE0F",
    "test" => "\u2705",
    "perf" => "\u26A1",
    "ci" => "\U0001F916",
    "build" => "\U0001F4E6",
    "revert" => "\u23EA",
    "style" => "\U0001F3A8"
  }

  defp emojify_subject(nil), do: "(no subject)"

  defp emojify_subject(subject) do
    case Regex.run(~r/^(\w+)(?:\([^)]*\))?:\s*(.*)$/i, subject) do
      [_full, type, rest] ->
        case Map.get(@conventional_commit_emojis, String.downcase(type)) do
          nil -> subject
          emoji -> "#{emoji} #{rest}"
        end

      _ ->
        subject
    end
  end

  defp delta_badge(%{counts: nil} = assigns) do
    ~H"""
    <span class="delta-chip">
      <span class="delta-label">{@label}</span>
      <span class="delta-unavailable">&mdash;</span>
    </span>
    """
  end

  defp delta_badge(assigns) do
    ~H"""
    <span class="delta-chip">
      <span class="delta-label">{@label}</span>
      <span class="delta-added">+{@counts.added}</span>
      <span class="delta-changed">~{@counts.changed}</span>
      <span class="delta-removed">-{@counts.removed}</span>
    </span>
    """
  end

  defp badge_text(:observed_in_session, _confidence), do: "Verified"

  defp badge_text(_type, confidence) do
    "Inferred #{round(confidence * 100)}%"
  end

  defp badge_class(:observed_in_session), do: "badge badge-verified"
  defp badge_class(_), do: "badge badge-inferred"

  defp distilled_badge(%{status: :completed} = assigns) do
    ~H"""
    <span class="badge text-xs">Summary</span>
    """
  end

  defp distilled_badge(%{status: :pending} = assigns) do
    ~H"""
    <span class="badge text-xs text-muted">Summary pending</span>
    """
  end

  defp distilled_badge(%{status: :error} = assigns) do
    ~H"""
    <span class="badge text-xs text-error">Summary failed</span>
    """
  end

  defp distilled_badge(assigns) do
    ~H"""
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container" data-testid="history-root">
      <div class="page-header">
        <h1>Commit History</h1>
      </div>

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

        <div>
          <label class="filter-label">Branch</label>
          <div class="filter-bar">
            <button
              phx-click="filter_branch"
              phx-value-branch="all"
              class={"filter-btn#{if @selected_branch == nil, do: " is-active"}"}
            >
              All
            </button>
            <button
              :for={branch <- @branches}
              phx-click="filter_branch"
              phx-value-branch={branch}
              class={"filter-btn#{if @selected_branch == branch, do: " is-active"}"}
            >
              {branch}
            </button>
          </div>
        </div>
      </div>

      <%= if @rows == [] do %>
        <div class="empty-state">
          No commits found for the selected filters.
        </div>
      <% else %>
        <div :for={row <- @rows} class="history-commit-card">
          <div class="history-commit-header">
            <a href={"/history/commits/#{row.commit.id}"} class="history-commit-hash">
              {String.slice(row.commit.commit_hash, 0, 8)}
            </a>
            <div class="history-commit-message">
              <span class="history-commit-subject">
                {emojify_subject(row.commit.subject)}
              </span>
              <div
                :if={row.commit.body not in [nil, ""]}
                class="history-commit-body"
              >
                {row.commit.body}
              </div>
            </div>
            <span class="history-commit-branch">
              {row.commit.git_branch || "\u2014"}
            </span>
            <span class="history-commit-time">
              {format_timestamp(row.commit.committed_at || row.commit.inserted_at)}
            </span>
          </div>

          <div :if={Map.has_key?(row, :delta_summary)} class="history-delta-row">
            <.delta_badge label="product" counts={row.delta_summary && row.delta_summary.product} />
            <.delta_badge label="tests" counts={row.delta_summary && row.delta_summary.tests} />
          </div>

          <%= if row.sessions == [] do %>
            <div class="history-session-empty">No linked sessions.</div>
          <% else %>
          <div :for={entry <- row.sessions} class="history-session-entry">
            <a href={"/sessions/#{entry.session.session_id}"} class="history-session-link">
              {SessionPresenter.primary_label(entry.session)}
            </a>
            <.distilled_badge status={entry.session.distilled_status} />
            <span class="history-session-project">
              {entry.project.name}
            </span>
            <span class="text-muted text-xs">
              {format_timestamp(entry.session.started_at || entry.session.inserted_at)}
            </span>
            <span :for={link_type <- entry.link_types} class={badge_class(link_type)}>
              {badge_text(link_type, entry.max_confidence)}
            </span>
          </div>
          <% end %>
        </div>

        <%= if @has_more do %>
          <div class="load-more">
            <button class="btn btn-primary" phx-click="load_more" phx-disable-with="Loading...">
              Load more
            </button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
