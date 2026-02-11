defmodule SpotterWeb.PaneListLive do
  use Phoenix.LiveView

  alias Spotter.Services.SessionRegistry
  alias Spotter.Services.Tmux
  alias Spotter.Transcripts.Jobs.SyncTranscripts

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Spotter.PubSub, "sync:progress")
    end

    {:ok,
     socket
     |> assign(panes: [], claude_panes: [], loading: true)
     |> assign(sync_status: %{}, sync_stats: %{})
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
      |> Ash.Query.load(sessions: Ash.Query.sort(Spotter.Transcripts.Session, started_at: :desc))
      |> Ash.read!()

    assign(socket, projects: projects)
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
          <div :for={project <- @projects} style="margin-bottom: 1.5rem;">
            <div style="display: flex; align-items: center; gap: 0.75rem; margin-bottom: 0.25rem;">
              <h3 style="margin: 0; color: #ccc;">
                {project.name}
                <span style="color: #666; font-weight: normal; font-size: 0.85em;">
                  ({length(project.sessions)} sessions)
                </span>
              </h3>
              <.sync_indicator status={Map.get(@sync_status, project.name)} stats={Map.get(@sync_stats, project.name)} />
            </div>

            <%= if project.sessions == [] do %>
              <div style="padding: 0.5rem; color: #666; font-size: 0.9em;">No sessions yet.</div>
            <% else %>
              <table>
                <thead>
                  <tr>
                    <th>Session</th>
                    <th>Branch</th>
                    <th>Messages</th>
                    <th>Started</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={session <- project.sessions}>
                    <td>{session_label(session)}</td>
                    <td>{session.git_branch || "—"}</td>
                    <td>{session.message_count || 0}</td>
                    <td>{relative_time(session.started_at)}</td>
                    <td>
                      <button
                        phx-click="review_session"
                        phx-value-session-id={session.session_id}
                        style="padding: 0.2rem 0.6rem; background: #2d4a2d; border: none; border-radius: 4px; color: #7ec87e; cursor: pointer; font-size: 0.8em;"
                      >
                        Review
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
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
