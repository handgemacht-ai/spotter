defmodule SpotterWeb.HistoryLive do
  use Phoenix.LiveView

  alias Spotter.Services.CommitHistory

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
       selected_project_id: nil,
       selected_branch: default_branch,
       rows: [],
       next_cursor: nil,
       has_more: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = parse_project_id(params["project_id"])

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
    project_id = parse_project_id(raw_id)

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

      {:noreply,
       assign(socket,
         rows: socket.assigns.rows ++ result.rows,
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

    assign(socket,
      rows: result.rows,
      next_cursor: result.cursor,
      has_more: result.has_more
    )
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

  defp parse_branch(nil, _valid), do: nil
  defp parse_branch("", _valid), do: nil
  defp parse_branch("all", _valid), do: nil
  defp parse_branch(branch, valid) when is_list(valid), do: if(branch in valid, do: branch)

  defp format_timestamp(nil), do: "\u2014"

  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp badge_text(:observed_in_session, _confidence), do: "Verified"

  defp badge_text(_type, confidence) do
    "Inferred #{round(confidence * 100)}%"
  end

  defp badge_style(:observed_in_session),
    do:
      "background: #1a4a2d; color: #4ade80; padding: 0.15rem 0.4rem; border-radius: 3px; font-size: 0.75em; margin-right: 0.25rem;"

  defp badge_style(_),
    do:
      "background: #3a3a1a; color: #d4c474; padding: 0.15rem 0.4rem; border-radius: 3px; font-size: 0.75em; margin-right: 0.25rem;"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <h1>Commit History</h1>

      <div style="display: flex; gap: 2rem; margin-bottom: 1rem; flex-wrap: wrap;">
        <div>
          <label style="display: block; color: #aaa; font-size: 0.85em; margin-bottom: 0.25rem;">
            Project
          </label>
          <div style="display: flex; gap: 0.3rem; flex-wrap: wrap;">
            <button
              phx-click="filter_project"
              phx-value-project-id="all"
              style={"padding: 0.3rem 0.6rem; border: none; border-radius: 4px; cursor: pointer; font-size: 0.85em; color: #e0e0e0; background: #{if @selected_project_id == nil, do: "#1a6b3c", else: "#333"};"}
            >
              All
            </button>
            <button
              :for={project <- @projects}
              phx-click="filter_project"
              phx-value-project-id={project.id}
              style={"padding: 0.3rem 0.6rem; border: none; border-radius: 4px; cursor: pointer; font-size: 0.85em; color: #e0e0e0; background: #{if @selected_project_id == project.id, do: "#1a6b3c", else: "#333"};"}
            >
              {project.name}
            </button>
          </div>
        </div>

        <div>
          <label style="display: block; color: #aaa; font-size: 0.85em; margin-bottom: 0.25rem;">
            Branch
          </label>
          <div style="display: flex; gap: 0.3rem; flex-wrap: wrap;">
            <button
              phx-click="filter_branch"
              phx-value-branch="all"
              style={"padding: 0.3rem 0.6rem; border: none; border-radius: 4px; cursor: pointer; font-size: 0.85em; color: #e0e0e0; background: #{if @selected_branch == nil, do: "#1a6b3c", else: "#333"};"}
            >
              All
            </button>
            <button
              :for={branch <- @branches}
              phx-click="filter_branch"
              phx-value-branch={branch}
              style={"padding: 0.3rem 0.6rem; border: none; border-radius: 4px; cursor: pointer; font-size: 0.85em; color: #e0e0e0; background: #{if @selected_branch == branch, do: "#1a6b3c", else: "#333"};"}
            >
              {branch}
            </button>
          </div>
        </div>
      </div>

      <%= if @rows == [] do %>
        <div style="padding: 2rem; color: #888; text-align: center;">
          No commits found for the selected filters.
        </div>
      <% else %>
        <div :for={row <- @rows} style="border: 1px solid #333; border-radius: 6px; margin-bottom: 0.75rem; padding: 0.75rem;">
          <div style="display: flex; align-items: baseline; gap: 0.75rem; margin-bottom: 0.5rem;">
            <code style="color: #f0c040; font-size: 0.9em;">
              {String.slice(row.commit.commit_hash, 0, 8)}
            </code>
            <span style="flex: 1; color: #e0e0e0;">
              {row.commit.subject || "(no subject)"}
            </span>
            <span style="color: #888; font-size: 0.85em;">
              {row.commit.git_branch || "\u2014"}
            </span>
            <span style="color: #666; font-size: 0.8em;">
              {format_timestamp(row.commit.committed_at || row.commit.inserted_at)}
            </span>
          </div>

          <div :for={entry <- row.sessions} style="margin-left: 1.5rem; padding: 0.4rem 0; border-top: 1px solid #2a2a2a;">
            <div style="display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap;">
              <a
                href={"/sessions/#{entry.session.session_id}"}
                style="color: #64b5f6; text-decoration: none; font-size: 0.9em;"
              >
                {entry.session.slug || String.slice(to_string(entry.session.session_id), 0, 8)}
              </a>
              <span style="color: #888; font-size: 0.8em;">
                {entry.project.name}
              </span>
              <span style="color: #666; font-size: 0.8em;">
                {format_timestamp(entry.session.started_at || entry.session.inserted_at)}
              </span>
              <span :for={link_type <- entry.link_types} style={badge_style(link_type)}>
                {badge_text(link_type, entry.max_confidence)}
              </span>
            </div>
          </div>
        </div>

        <%= if @has_more do %>
          <div style="text-align: center; margin: 1rem 0;">
            <button
              phx-click="load_more"
              phx-disable-with="Loading..."
              style="padding: 0.4rem 1rem; background: #1a3a52; border: 1px solid #2a4a6a; border-radius: 4px; color: #64b5f6; cursor: pointer;"
            >
              Load more
            </button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
