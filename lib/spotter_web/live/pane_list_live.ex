defmodule SpotterWeb.PaneListLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  alias Spotter.Services.SessionRegistry
  alias Spotter.Services.Tmux
  alias Spotter.Transcripts.Jobs.SyncTranscripts
  alias Spotter.Transcripts.{Session, SessionPresenter, ToolCall}

  require Ash.Query

  @sessions_per_page 20

  computer :project_filter do
    input :selected_project_id do
      initial nil
    end

    val :projects do
      compute(fn _inputs ->
        try do
          Spotter.Transcripts.Project |> Ash.read!()
        rescue
          _ -> []
        end
      end)

      depends_on([])
    end

    event :filter_project do
      handle(fn _values, %{"project-id" => project_id} ->
        if project_id == "all" do
          %{selected_project_id: nil}
        else
          %{selected_project_id: project_id}
        end
      end)
    end
  end

  computer :session_data do
    input :projects do
      initial []
    end
  end

  computer :tool_call_stats do
    input :session_ids do
      initial []
    end

    val :stats do
      compute(fn %{session_ids: session_ids} ->
        if session_ids == [] do
          %{}
        else
          try do
            ToolCall
            |> Ash.Query.filter(session_id in ^session_ids)
            |> Ash.read!()
            |> Enum.group_by(& &1.session_id)
            |> Map.new(fn {sid, calls} ->
              failed = Enum.count(calls, & &1.is_error)
              {sid, %{total: length(calls), failed: failed}}
            end)
          rescue
            _ -> %{}
          end
        end
      end)
    end
  end

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
     |> mount_computers()
     |> load_panes()
     |> load_session_data()}
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
    {:noreply, load_session_data(socket)}
  end

  def handle_event("unhide_session", %{"id" => id}, socket) do
    session = Ash.get!(Spotter.Transcripts.Session, id)
    Ash.update!(session, %{}, action: :unhide)
    {:noreply, load_session_data(socket)}
  end

  def handle_event("toggle_hidden_section", %{"project-id" => project_id}, socket) do
    hidden_expanded = socket.assigns.hidden_expanded
    current = Map.get(hidden_expanded, project_id, false)
    {:noreply, assign(socket, hidden_expanded: Map.put(hidden_expanded, project_id, !current))}
  end

  def handle_event(
        "load_more_sessions",
        %{"project-id" => project_id, "visibility" => visibility},
        socket
      ) do
    visibility = String.to_existing_atom(visibility)
    {:noreply, append_session_page(socket, project_id, visibility)}
  end

  def handle_event("sync_transcripts", _params, socket) do
    SyncTranscripts.sync_all()

    project_names = Enum.map(socket.assigns.session_data_projects, & &1.name)

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
     |> load_session_data()}
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

  defp load_session_data(socket) do
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

    session_ids = extract_session_ids(projects)

    socket
    |> update_computer_inputs(:session_data, %{projects: projects})
    |> update_computer_inputs(:tool_call_stats, %{session_ids: session_ids})
  end

  defp append_session_page(socket, project_id, visibility) do
    projects = socket.assigns.session_data_projects
    project = Enum.find(projects, &(&1.id == project_id))
    has_more_key = :"#{visibility}_has_more"

    if project && Map.get(project, has_more_key) do
      do_append_session_page(socket, project, projects, visibility)
    else
      socket
    end
  end

  defp do_append_session_page(socket, project, projects, visibility) do
    cursor_key = :"#{visibility}_cursor"
    sessions_key = :"#{visibility}_sessions"
    has_more_key = :"#{visibility}_has_more"

    {new_sessions, meta} =
      load_project_sessions(project.id, visibility, after: Map.get(project, cursor_key))

    updated_project =
      project
      |> Map.update!(sessions_key, &(&1 ++ new_sessions))
      |> Map.put(cursor_key, meta.next_cursor)
      |> Map.put(has_more_key, meta.has_more)

    updated_projects =
      Enum.map(projects, fn p ->
        if p.id == project.id, do: updated_project, else: p
      end)

    session_ids = extract_session_ids(updated_projects)

    socket
    |> update_computer_inputs(:session_data, %{projects: updated_projects})
    |> update_computer_inputs(:tool_call_stats, %{session_ids: session_ids})
  end

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

  defp extract_session_ids(projects) do
    projects
    |> Enum.flat_map(fn p -> p.visible_sessions ++ p.hidden_sessions end)
    |> Enum.map(& &1.id)
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

        <%= if @session_data_projects == [] do %>
          <div class="empty-state" style="padding: 1rem; color: #888;">
            No projects synced yet. Click Sync to start.
          </div>
        <% else %>
          <div :if={length(@session_data_projects) > 1} style="display: flex; gap: 0.5rem; flex-wrap: wrap; margin-bottom: 1rem;">
            <button
              phx-click={event(:project_filter, :filter_project)}
              phx-value-project-id="all"
              style={"padding: 0.4rem 0.8rem; border: none; border-radius: 4px; cursor: pointer; font-size: 0.85em; color: #e0e0e0; background: #{if @project_filter_selected_project_id == nil, do: "#1a6b3c", else: "#333"};"}
            >
              All ({Enum.sum(Enum.map(@session_data_projects, &length(&1.visible_sessions)))})
            </button>
            <button
              :for={project <- @session_data_projects}
              phx-click={event(:project_filter, :filter_project)}
              phx-value-project-id={project.id}
              style={"padding: 0.4rem 0.8rem; border: none; border-radius: 4px; cursor: pointer; font-size: 0.85em; color: #e0e0e0; background: #{if @project_filter_selected_project_id == project.id, do: "#1a6b3c", else: "#333"};"}
            >
              {project.name} ({length(project.visible_sessions)})
            </button>
          </div>

          <div :for={project <- @session_data_projects} :if={@project_filter_selected_project_id == nil or @project_filter_selected_project_id == project.id} style="margin-bottom: 1.5rem;">
            <div style="display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.25rem;">
              <h3 style="margin: 0; color: #ccc;">
                {project.name}
                <span style="color: #666; font-weight: normal; font-size: 0.85em;">
                  ({length(project.visible_sessions)} sessions)
                </span>
              </h3>
              <a
                href={"/projects/#{project.id}/review"}
                style="padding: 0.2rem 0.6rem; background: #1a4a6b; border-radius: 4px; color: #64b5f6; text-decoration: none; font-size: 0.8em;"
              >
                Review
              </a>
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
                      <td>
                        <div>{SessionPresenter.primary_label(session)}</div>
                        <div style="font-size: 0.75em; color: #888;">{SessionPresenter.secondary_label(session)}</div>
                      </td>
                      <td>{session.git_branch || "—"}</td>
                      <td>{session.message_count || 0}</td>
                      <td>
                        <% stats = Map.get(@tool_call_stats_stats, session.id) %>
                        <%= cond do %>
                          <% stats && stats.total > 0 && stats.failed > 0 -> %>
                            <span>{stats.total}</span> <span style="color: #f87171;">({stats.failed} failed)</span>
                          <% stats && stats.total > 0 -> %>
                            <span>{stats.total}</span>
                          <% true -> %>
                            <span>—</span>
                        <% end %>
                      </td>
                      <td>
                        <% started = SessionPresenter.started_display(session.started_at) %>
                        <%= if started do %>
                          <div>{started.relative}</div>
                          <div style="font-size: 0.75em; color: #888;">{started.absolute}</div>
                        <% else %>
                          —
                        <% end %>
                      </td>
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
                          <td>
                            <div>{SessionPresenter.primary_label(session)}</div>
                            <div style="font-size: 0.75em; color: #888;">{SessionPresenter.secondary_label(session)}</div>
                          </td>
                          <td>{session.git_branch || "—"}</td>
                          <td>{session.message_count || 0}</td>
                          <td>
                            <% stats = Map.get(@tool_call_stats_stats, session.id) %>
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
