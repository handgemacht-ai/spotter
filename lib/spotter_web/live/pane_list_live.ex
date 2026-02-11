defmodule SpotterWeb.PaneListLive do
  use Phoenix.LiveView

  alias Spotter.Services.SessionRegistry
  alias Spotter.Services.Tmux
  alias Spotter.Transcripts.Jobs.SyncTranscripts
  alias Spotter.Transcripts.{Session, ToolCall}

  require Ash.Query

  @sessions_per_page 20

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Spotter.PubSub, "sync:progress")
    end

    {:ok,
     socket
     |> assign(panes: [], claude_panes: [], loading: true)
     |> assign(sync_status: %{}, sync_stats: %{})
     |> assign(hidden_expanded: %{})
     |> assign(selected_project_id: nil)
     |> load_panes()
     |> load_projects()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_panes(socket)}
  end

  def handle_event("review_session", %{"session-id" => session_id}, socket) do
    Task.start(fn -> Tmux.launch_review_session(session_id) end)
    {:noreply, push_navigate(socket, to: "/sessions/#{session_id}")}
  end

  def handle_event("hide_session", %{"id" => id}, socket) do
    session = Ash.get!(Spotter.Transcripts.Session, id)
    Ash.update!(session, %{}, action: :hide)
    {:noreply, load_projects(socket)}
  end

  def handle_event("unhide_session", %{"id" => id}, socket) do
    session = Ash.get!(Spotter.Transcripts.Session, id)
    Ash.update!(session, %{}, action: :unhide)
    {:noreply, load_projects(socket)}
  end

  def handle_event("toggle_hidden_section", %{"project-id" => project_id}, socket) do
    hidden_expanded = socket.assigns.hidden_expanded
    current = Map.get(hidden_expanded, project_id, false)
    {:noreply, assign(socket, hidden_expanded: Map.put(hidden_expanded, project_id, !current))}
  end

  def handle_event("filter_project", %{"project-id" => "all"}, socket) do
    {:noreply, assign(socket, selected_project_id: nil)}
  end

  def handle_event("filter_project", %{"project-id" => project_id}, socket) do
    {:noreply, assign(socket, selected_project_id: project_id)}
  end

  def handle_event(
        "load_more_sessions",
        %{"project-id" => project_id, "visibility" => visibility},
        socket
      ) do
    visibility = String.to_existing_atom(visibility)
    socket = append_session_page(socket, project_id, visibility)
    {:noreply, socket}
  end

  def handle_event("sync_transcripts", _params, socket) do
    SyncTranscripts.sync_all()

    project_names = Enum.map(socket.assigns.projects, & &1.name)

    sync_status =
      Map.new(project_names, fn name -> {name, :syncing} end)

    {:noreply, assign(socket, sync_status: sync_status)}
  end

  @impl true
  def handle_info({:sync_started, %{project: name}}, socket) do
    {:noreply, assign(socket, sync_status: Map.put(socket.assigns.sync_status, name, :syncing))}
  end

  def handle_info({:sync_completed, %{project: name} = data}, socket) do
    {:noreply,
     socket
     |> assign(sync_status: Map.put(socket.assigns.sync_status, name, :completed))
     |> assign(sync_stats: Map.put(socket.assigns.sync_stats, name, data))
     |> load_projects()}
  end

  def handle_info({:sync_error, %{project: name} = data}, socket) do
    {:noreply,
     socket
     |> assign(sync_status: Map.put(socket.assigns.sync_status, name, :error))
     |> assign(sync_stats: Map.put(socket.assigns.sync_stats, name, data))}
  end

  defp load_panes(socket) do
    {claude_panes, other_panes} =
      case Tmux.list_panes() do
        {:ok, panes} ->
          Enum.split_with(panes, fn p ->
            p.pane_current_command in ["claude", "claude-code"] or
              String.contains?(p.pane_title, "claude")
          end)

        {:error, _} ->
          {[], []}
      end

    # Only show plugin-registered panes, exclude review sessions
    registered_panes =
      claude_panes
      |> Enum.reject(&String.starts_with?(&1.session_name, "spotter-review-"))
      |> Enum.filter(&SessionRegistry.get_session_id(&1.pane_id))

    assign(socket, panes: other_panes, claude_panes: registered_panes, loading: false)
  end

  defp load_projects(socket) do
    projects =
      Spotter.Transcripts.Project
      |> Ash.read!()
      |> Enum.map(fn project ->
        {visible, visible_meta} = load_project_sessions(project.id, :visible)
        {hidden, hidden_meta} = load_project_sessions(project.id, :hidden)

        Map.merge(project, %{
          visible_sessions: visible,
          hidden_sessions: hidden,
          visible_cursor: visible_meta.next_cursor,
          visible_has_more: visible_meta.has_more,
          hidden_cursor: hidden_meta.next_cursor,
          hidden_has_more: hidden_meta.has_more
        })
      end)

    tool_call_stats = load_tool_call_stats(projects)

    assign(socket, projects: projects, tool_call_stats: tool_call_stats)
  end

  defp append_session_page(socket, project_id, visibility) do
    project = Enum.find(socket.assigns.projects, &(&1.id == project_id))
    keys = pagination_keys(visibility)

    if project && Map.get(project, keys.has_more) do
      do_append_session_page(socket, project, visibility, keys)
    else
      socket
    end
  end

  defp do_append_session_page(socket, project, visibility, keys) do
    {new_sessions, meta} =
      load_project_sessions(project.id, visibility, after: Map.get(project, keys.cursor))

    updated_project =
      project
      |> Map.update!(keys.sessions, &(&1 ++ new_sessions))
      |> Map.put(keys.cursor, meta.next_cursor)
      |> Map.put(keys.has_more, meta.has_more)

    projects =
      Enum.map(socket.assigns.projects, fn p ->
        if p.id == project.id, do: updated_project, else: p
      end)

    new_stats = load_tool_call_stats_for(Enum.map(new_sessions, & &1.id))

    assign(socket,
      projects: projects,
      tool_call_stats: Map.merge(socket.assigns.tool_call_stats, new_stats)
    )
  end

  defp pagination_keys(:visible),
    do: %{cursor: :visible_cursor, has_more: :visible_has_more, sessions: :visible_sessions}

  defp pagination_keys(:hidden),
    do: %{cursor: :hidden_cursor, has_more: :hidden_has_more, sessions: :hidden_sessions}

  defp load_project_sessions(project_id, visibility, opts \\ []) do
    cursor = Keyword.get(opts, :after)

    query =
      Session
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.Query.sort(started_at: :desc)

    query =
      case visibility do
        :visible -> Ash.Query.filter(query, is_nil(hidden_at))
        :hidden -> Ash.Query.filter(query, not is_nil(hidden_at))
      end

    page_opts = [limit: @sessions_per_page]
    page_opts = if cursor, do: Keyword.put(page_opts, :after, cursor), else: page_opts

    page = query |> Ash.Query.page(page_opts) |> Ash.read!()

    meta = %{has_more: page.more?, next_cursor: page.after}
    {page.results, meta}
  end

  defp load_tool_call_stats(projects) do
    session_ids =
      projects
      |> Enum.flat_map(fn p -> p.visible_sessions ++ p.hidden_sessions end)
      |> Enum.map(& &1.id)

    load_tool_call_stats_for(session_ids)
  end

  defp load_tool_call_stats_for([]), do: %{}

  defp load_tool_call_stats_for(session_ids) do
    ToolCall
    |> Ash.Query.filter(session_id in ^session_ids)
    |> Ash.read!()
    |> Enum.group_by(& &1.session_id)
    |> Map.new(fn {sid, calls} ->
      failed = Enum.count(calls, & &1.is_error)
      {sid, %{total: length(calls), failed: failed}}
    end)
  end

  defp relative_time(nil), do: "—"

  defp relative_time(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp session_label(session) do
    session.slug || String.slice(session.session_id, 0, 8)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 1rem;">
        <h1>Spotter - Tmux Panes</h1>
        <div style="display: flex; gap: 0.5rem;">
          <a href="/debug" style="padding: 0.4rem 0.8rem; background: #2d4a2d; border-radius: 4px; color: #7ec87e; text-decoration: none; font-size: 0.85rem;">
            Debug Terminal
          </a>
          <button phx-click="refresh">Refresh</button>
        </div>
      </div>

      <%!-- Session Transcripts Section --%>
      <div style="margin-bottom: 2rem;">
        <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 0.5rem;">
          <h2 style="color: #a0d0f0; margin: 0;">Session Transcripts</h2>
          <button phx-click="sync_transcripts">Sync</button>
        </div>

        <%= if @projects == [] do %>
          <div class="empty-state" style="padding: 1rem; color: #888;">
            No projects synced yet. Click Sync to start.
          </div>
        <% else %>
          <div :if={length(@projects) > 1} style="display: flex; gap: 0.5rem; flex-wrap: wrap; margin-bottom: 1rem;">
            <button
              phx-click="filter_project"
              phx-value-project-id="all"
              style={"padding: 0.4rem 0.8rem; border: none; border-radius: 4px; cursor: pointer; font-size: 0.85em; color: #e0e0e0; background: #{if @selected_project_id == nil, do: "#1a6b3c", else: "#333"};"}
            >
              All ({Enum.sum(Enum.map(@projects, &length(&1.visible_sessions)))})
            </button>
            <button
              :for={project <- @projects}
              phx-click="filter_project"
              phx-value-project-id={project.id}
              style={"padding: 0.4rem 0.8rem; border: none; border-radius: 4px; cursor: pointer; font-size: 0.85em; color: #e0e0e0; background: #{if @selected_project_id == project.id, do: "#1a6b3c", else: "#333"};"}
            >
              {project.name} ({length(project.visible_sessions)})
            </button>
          </div>

          <div :for={project <- @projects} :if={@selected_project_id == nil or @selected_project_id == project.id} style="margin-bottom: 1.5rem;">
            <div style="display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.25rem;">
              <h3 style="margin: 0; color: #ccc;">
                {project.name}
                <span style="color: #666; font-weight: normal; font-size: 0.85em;">
                  ({length(project.visible_sessions)} sessions)
                </span>
              </h3>
              <.sync_indicator status={Map.get(@sync_status, project.name)} stats={Map.get(@sync_stats, project.name)} />
            </div>

            <%= if project.visible_sessions == [] and project.hidden_sessions == [] do %>
              <div style="padding: 0.5rem; color: #666; font-size: 0.9em;">No sessions yet.</div>
            <% else %>
              <%= if project.visible_sessions != [] do %>
                <table>
                  <thead>
                    <tr>
                      <th>Session</th>
                      <th>Branch</th>
                      <th>Messages</th>
                      <th>Tools</th>
                      <th>Started</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={session <- project.visible_sessions}>
                      <td>{session_label(session)}</td>
                      <td>{session.git_branch || "—"}</td>
                      <td>{session.message_count || 0}</td>
                      <td>
                        <% stats = Map.get(@tool_call_stats, session.id) %>
                        <%= cond do %>
                          <% stats && stats.total > 0 && stats.failed > 0 -> %>
                            <span>{stats.total}</span> <span style="color: #f87171;">({stats.failed} failed)</span>
                          <% stats && stats.total > 0 -> %>
                            <span>{stats.total}</span>
                          <% true -> %>
                            <span>—</span>
                        <% end %>
                      </td>
                      <td>{relative_time(session.started_at)}</td>
                      <td style="display: flex; gap: 0.3rem;">
                        <button
                          phx-click="review_session"
                          phx-value-session-id={session.session_id}
                          style="padding: 0.2rem 0.6rem; background: #2d4a2d; border: none; border-radius: 4px; color: #7ec87e; cursor: pointer; font-size: 0.8em;"
                        >
                          Review
                        </button>
                        <button
                          phx-click="hide_session"
                          phx-value-id={session.id}
                          style="padding: 0.2rem 0.5rem; background: #4a3a2d; border: none; border-radius: 4px; color: #d4a574; cursor: pointer; font-size: 0.8em;"
                        >
                          Hide
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
                <%= if project.visible_has_more do %>
                  <div style="text-align: center; margin-top: 0.5rem;">
                    <button
                      phx-click="load_more_sessions"
                      phx-value-project-id={project.id}
                      phx-value-visibility="visible"
                      phx-disable-with="Loading..."
                      style="padding: 0.3rem 0.8rem; background: #1a3a52; border: 1px solid #2a4a6a; border-radius: 4px; color: #64b5f6; cursor: pointer; font-size: 0.8em;"
                    >
                      Load more sessions ({length(project.visible_sessions)} shown)
                    </button>
                  </div>
                <% end %>
              <% end %>

              <%= if project.hidden_sessions != [] do %>
                <div style="margin-top: 0.5rem;">
                  <button
                    phx-click="toggle_hidden_section"
                    phx-value-project-id={project.id}
                    style="background: none; border: none; color: #888; cursor: pointer; font-size: 0.85em; padding: 0.2rem 0;"
                  >
                    <%= if Map.get(@hidden_expanded, project.id, false) do %>
                      ▼ Hidden sessions ({length(project.hidden_sessions)})
                    <% else %>
                      ▶ Hidden sessions ({length(project.hidden_sessions)})
                    <% end %>
                  </button>

                  <%= if Map.get(@hidden_expanded, project.id, false) do %>
                    <table style="opacity: 0.7;">
                      <thead>
                        <tr>
                          <th>Session</th>
                          <th>Branch</th>
                          <th>Messages</th>
                          <th>Tools</th>
                          <th>Hidden</th>
                          <th></th>
                        </tr>
                      </thead>
                      <tbody>
                        <tr :for={session <- project.hidden_sessions}>
                          <td>{session_label(session)}</td>
                          <td>{session.git_branch || "—"}</td>
                          <td>{session.message_count || 0}</td>
                          <td>
                            <% stats = Map.get(@tool_call_stats, session.id) %>
                            <%= cond do %>
                              <% stats && stats.total > 0 && stats.failed > 0 -> %>
                                <span>{stats.total}</span> <span style="color: #f87171;">({stats.failed} failed)</span>
                              <% stats && stats.total > 0 -> %>
                                <span>{stats.total}</span>
                              <% true -> %>
                                <span>—</span>
                            <% end %>
                          </td>
                          <td>{relative_time(session.hidden_at)}</td>
                          <td>
                            <button
                              phx-click="unhide_session"
                              phx-value-id={session.id}
                              style="padding: 0.2rem 0.5rem; background: #2d4a2d; border: none; border-radius: 4px; color: #7ec87e; cursor: pointer; font-size: 0.8em;"
                            >
                              Unhide
                            </button>
                          </td>
                        </tr>
                      </tbody>
                    </table>
                    <%= if project.hidden_has_more do %>
                      <div style="text-align: center; margin-top: 0.5rem;">
                        <button
                          phx-click="load_more_sessions"
                          phx-value-project-id={project.id}
                          phx-value-visibility="hidden"
                          phx-disable-with="Loading..."
                          style="padding: 0.3rem 0.8rem; background: #1a3a52; border: 1px solid #2a4a6a; border-radius: 4px; color: #64b5f6; cursor: pointer; font-size: 0.8em;"
                        >
                          Load more hidden ({length(project.hidden_sessions)} shown)
                        </button>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>

      <%= if @claude_panes != [] do %>
        <h2 style="color: #d4a574; margin-bottom: 0.5rem;">Claude Code Sessions</h2>
        <.pane_table panes={@claude_panes} badge="claude" />
      <% end %>

      <%= if @panes != [] do %>
        <h2 style="margin-top: 1.5rem; margin-bottom: 0.5rem;">Other Panes</h2>
        <.pane_table panes={@panes} badge="other" />
      <% end %>

      <%= if @panes == [] and @claude_panes == [] and not @loading do %>
        <div class="empty-state">
          <p>No tmux panes found.</p>
          <p style="margin-top: 0.5rem;">Make sure tmux is running with active sessions.</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp sync_indicator(%{status: nil} = assigns), do: ~H""
  defp sync_indicator(%{status: :idle} = assigns), do: ~H""

  defp sync_indicator(%{status: :syncing} = assigns) do
    ~H"""
    <span style="color: #f0c040; font-size: 0.85em; animation: pulse 1.5s infinite;">syncing...</span>
    """
  end

  defp sync_indicator(%{status: :completed, stats: stats} = assigns) do
    assigns = assign(assigns, :stats, stats)

    ~H"""
    <span style="color: #4ade80; font-size: 0.85em;">
      ✓ {@stats.dirs_synced} dirs, {@stats.sessions_synced} sessions in {@stats.duration_ms}ms
    </span>
    """
  end

  defp sync_indicator(%{status: :error, stats: stats} = assigns) do
    assigns = assign(assigns, :stats, stats)

    ~H"""
    <span style="color: #f87171; font-size: 0.85em;">✗ {@stats.error}</span>
    """
  end

  defp pane_table(assigns) do
    ~H"""
    <table>
      <thead>
        <tr>
          <th>Pane ID</th>
          <th>Session</th>
          <th>Window</th>
          <th>Command</th>
          <th>Size</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr :for={pane <- @panes}>
          <td><span class={"badge badge-#{@badge}"}>{pane.pane_id}</span></td>
          <td>{pane.session_name}</td>
          <td>{pane.window_index}:{pane.pane_index}</td>
          <td>{pane.pane_current_command}</td>
          <td>{pane.pane_width}x{pane.pane_height}</td>
          <td><a href={"/sessions/#{SessionRegistry.get_session_id(pane.pane_id)}"}>Connect</a></td>
        </tr>
      </tbody>
    </table>
    """
  end
end
