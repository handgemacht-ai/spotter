defmodule SpotterWeb.PaneListLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  alias Spotter.Services.SessionRegistry
  alias Spotter.Services.Tmux
  alias Spotter.Transcripts.Jobs.SyncTranscripts
  alias Spotter.Transcripts.{Session, SessionPresenter, Subagent, ToolCall}

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
     |> assign(expanded_subagents: %{})
     |> assign(subagents_by_session: %{})
     |> mount_computers()
     |> load_panes()
     |> load_session_data()}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, load_panes(socket)}
  end

  def handle_event("review_session", %{"session-id" => session_id}, socket) do
    cwd = lookup_session_cwd(session_id)
    Task.start(fn -> Tmux.launch_review_session(session_id, cwd: cwd) end)
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

  def handle_event("toggle_subagents", %{"session-id" => session_id}, socket) do
    expanded = socket.assigns.expanded_subagents
    current = Map.get(expanded, session_id, false)
    {:noreply, assign(socket, expanded_subagents: Map.put(expanded, session_id, !current))}
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

  defp lookup_session_cwd(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %Session{cwd: cwd}} when is_binary(cwd) -> cwd
      _ -> nil
    end
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

    subagents_by_session = load_subagents_for_sessions(session_ids)

    socket
    |> assign(subagents_by_session: subagents_by_session)
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
    new_ids = Enum.map(new_sessions, & &1.id)
    new_subagents = load_subagents_for_sessions(new_ids)

    socket
    |> assign(subagents_by_session: Map.merge(socket.assigns.subagents_by_session, new_subagents))
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

  defp load_subagents_for_sessions([]), do: %{}

  defp load_subagents_for_sessions(session_ids) do
    Subagent
    |> Ash.Query.filter(session_id in ^session_ids)
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.read!()
    |> Enum.group_by(& &1.session_id)
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
      <div class="page-header">
        <h1>Dashboard</h1>
        <div class="page-header-actions">
          <button class="btn" phx-click="refresh">Refresh</button>
        </div>
      </div>

      <%!-- Session Transcripts Section --%>
      <div class="mb-4">
        <div class="page-header">
          <h2 class="section-heading">Session Transcripts</h2>
          <button class="btn" phx-click="sync_transcripts">Sync</button>
        </div>

        <%= if @session_data_projects == [] do %>
          <div class="empty-state">
            No projects synced yet. Click Sync to start.
          </div>
        <% else %>
          <div :if={length(@session_data_projects) > 1} class="filter-bar">
            <button
              phx-click={event(:project_filter, :filter_project)}
              phx-value-project-id="all"
              class={"filter-btn#{if @project_filter_selected_project_id == nil, do: " is-active"}"}
            >
              All ({Enum.sum(Enum.map(@session_data_projects, &length(&1.visible_sessions)))})
            </button>
            <button
              :for={project <- @session_data_projects}
              phx-click={event(:project_filter, :filter_project)}
              phx-value-project-id={project.id}
              class={"filter-btn#{if @project_filter_selected_project_id == project.id, do: " is-active"}"}
            >
              {project.name} ({length(project.visible_sessions)})
            </button>
          </div>

          <div
            :for={project <- @session_data_projects}
            :if={@project_filter_selected_project_id == nil or @project_filter_selected_project_id == project.id}
            class="project-section"
          >
            <div class="project-header">
              <h3>
                <span class="project-name">{project.name}</span>
                <span class="project-count">
                  ({length(project.visible_sessions)} sessions)
                </span>
              </h3>
              <.sync_indicator status={Map.get(@sync_status, project.name)} stats={Map.get(@sync_stats, project.name)} />
            </div>

            <%= if project.visible_sessions == [] and project.hidden_sessions == [] do %>
              <div class="text-muted text-sm">No sessions yet.</div>
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
                    <%= for session <- project.visible_sessions do %>
                      <% subagents = Map.get(@subagents_by_session, session.id, []) %>
                      <tr>
                        <td>
                          <div>{SessionPresenter.primary_label(session)}</div>
                          <div class="text-muted text-xs">{SessionPresenter.secondary_label(session)}</div>
                        </td>
                        <td>{session.git_branch || "—"}</td>
                        <td>
                          {session.message_count || 0}
                          <%= if subagents != [] do %>
                            <span
                              phx-click="toggle_subagents"
                              phx-value-session-id={session.id}
                              class="subagent-toggle"
                            >
                              {length(subagents)} agents
                              <%= if Map.get(@expanded_subagents, session.id, false), do: "▼", else: "▶" %>
                            </span>
                          <% end %>
                        </td>
                        <td>
                          <% stats = Map.get(@tool_call_stats_stats, session.id) %>
                          <%= cond do %>
                            <% stats && stats.total > 0 && stats.failed > 0 -> %>
                              <span>{stats.total}</span> <span class="text-error">({stats.failed} failed)</span>
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
                            <div class="text-muted text-xs">{started.absolute}</div>
                          <% else %>
                            —
                          <% end %>
                        </td>
                        <td class="flex gap-1">
                          <button class="btn btn-success" phx-click="review_session" phx-value-session-id={session.session_id}>
                            Review
                          </button>
                          <button class="btn" phx-click="hide_session" phx-value-id={session.id}>
                            Hide
                          </button>
                        </td>
                      </tr>
                      <%= if Map.get(@expanded_subagents, session.id, false) do %>
                        <tr :for={sa <- subagents} class="subagent-row">
                          <td>{sa.slug || String.slice(sa.agent_id, 0, 7)}</td>
                          <td></td>
                          <td>{sa.message_count || 0}</td>
                          <td></td>
                          <td>{relative_time(sa.started_at)}</td>
                          <td>
                            <a href={"/sessions/#{session.session_id}/agents/#{sa.agent_id}"} class="btn btn-success">
                              View
                            </a>
                          </td>
                        </tr>
                      <% end %>
                    <% end %>
                  </tbody>
                </table>
                <%= if project.visible_has_more do %>
                  <div class="load-more">
                    <button
                      class="btn"
                      phx-click="load_more_sessions"
                      phx-value-project-id={project.id}
                      phx-value-visibility="visible"
                      phx-disable-with="Loading..."
                    >
                      Load more sessions ({length(project.visible_sessions)} shown)
                    </button>
                  </div>
                <% end %>
              <% end %>

              <%= if project.hidden_sessions != [] do %>
                <div class="mt-2">
                  <button
                    class="hidden-toggle"
                    phx-click="toggle_hidden_section"
                    phx-value-project-id={project.id}
                  >
                    <%= if Map.get(@hidden_expanded, project.id, false) do %>
                      ▼ Hidden sessions ({length(project.hidden_sessions)})
                    <% else %>
                      ▶ Hidden sessions ({length(project.hidden_sessions)})
                    <% end %>
                  </button>

                  <%= if Map.get(@hidden_expanded, project.id, false) do %>
                    <table class="hidden-table">
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
                        <%= for session <- project.hidden_sessions do %>
                          <% subagents = Map.get(@subagents_by_session, session.id, []) %>
                          <tr>
                            <td>
                              <div>{SessionPresenter.primary_label(session)}</div>
                              <div class="text-muted text-xs">{SessionPresenter.secondary_label(session)}</div>
                            </td>
                            <td>{session.git_branch || "—"}</td>
                            <td>
                              {session.message_count || 0}
                              <%= if subagents != [] do %>
                                <span
                                  phx-click="toggle_subagents"
                                  phx-value-session-id={session.id}
                                  class="subagent-toggle"
                                >
                                  {length(subagents)} agents
                                  <%= if Map.get(@expanded_subagents, session.id, false), do: "▼", else: "▶" %>
                                </span>
                              <% end %>
                            </td>
                            <td>
                              <% stats = Map.get(@tool_call_stats_stats, session.id) %>
                              <%= cond do %>
                                <% stats && stats.total > 0 && stats.failed > 0 -> %>
                                  <span>{stats.total}</span> <span class="text-error">({stats.failed} failed)</span>
                                <% stats && stats.total > 0 -> %>
                                  <span>{stats.total}</span>
                                <% true -> %>
                                  <span>—</span>
                              <% end %>
                            </td>
                            <td>{relative_time(session.hidden_at)}</td>
                            <td>
                              <button class="btn btn-success" phx-click="unhide_session" phx-value-id={session.id}>
                                Unhide
                              </button>
                            </td>
                          </tr>
                          <%= if Map.get(@expanded_subagents, session.id, false) do %>
                            <tr :for={sa <- subagents} class="subagent-row">
                              <td>{sa.slug || String.slice(sa.agent_id, 0, 7)}</td>
                              <td></td>
                              <td>{sa.message_count || 0}</td>
                              <td></td>
                              <td>{relative_time(sa.started_at)}</td>
                              <td>
                                <a href={"/sessions/#{session.session_id}/agents/#{sa.agent_id}"} class="btn btn-success">
                                  View
                                </a>
                              </td>
                            </tr>
                          <% end %>
                        <% end %>
                      </tbody>
                    </table>
                    <%= if project.hidden_has_more do %>
                      <div class="load-more">
                        <button
                          class="btn"
                          phx-click="load_more_sessions"
                          phx-value-project-id={project.id}
                          phx-value-visibility="hidden"
                          phx-disable-with="Loading..."
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
        <h2 class="section-heading">Claude Code Sessions</h2>
        <.pane_table panes={@claude_panes} badge="agent" />
      <% end %>

      <%= if @panes != [] do %>
        <h2 class="section-heading mt-4">Other Panes</h2>
        <.pane_table panes={@panes} badge="terminal" />
      <% end %>

      <%= if @panes == [] and @claude_panes == [] and not @loading do %>
        <div class="empty-state">
          <p>No tmux panes found.</p>
          <p class="mt-2 text-muted">Make sure tmux is running with active sessions.</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp sync_indicator(%{status: nil} = assigns), do: ~H""
  defp sync_indicator(%{status: :idle} = assigns), do: ~H""

  defp sync_indicator(%{status: :syncing} = assigns) do
    ~H"""
    <span class="sync-syncing">syncing...</span>
    """
  end

  defp sync_indicator(%{status: :completed, stats: stats} = assigns) do
    assigns = assign(assigns, :stats, stats)

    ~H"""
    <span class="sync-completed">
      ✓ {@stats.dirs_synced} dirs, {@stats.sessions_synced} sessions in {@stats.duration_ms}ms
    </span>
    """
  end

  defp sync_indicator(%{status: :error, stats: stats} = assigns) do
    assigns = assign(assigns, :stats, stats)

    ~H"""
    <span class="sync-error">✗ {@stats.error}</span>
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
