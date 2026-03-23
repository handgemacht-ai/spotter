defmodule SpotterWeb.DashboardLive do
  use Phoenix.LiveView

  alias Spotter.Services.{SessionSliceQuery, SkillFolderReader}
  alias Spotter.Transcripts.{Session, SessionPresenter}
  import SpotterWeb.FolderComponents, only: [folder_card: 1]
  alias SpotterWeb.ProjectHelpers

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def mount(_params, _session, socket) do
    Tracer.with_span "spotter.dashboard.mount" do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Spotter.PubSub, "session_activity")
      end

      sessions = load_ongoing_sessions()
      Tracer.set_attribute("session_count", length(sessions))

      socket =
        socket
        |> assign(sessions: sessions)
        |> assign(finished_ids: MapSet.new())
        |> assign(projects: [])
        |> assign(current_project_id: nil)
        |> assign(skill_folders: [])
        |> assign(slices: [])

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {projects, current_project_id} =
      ProjectHelpers.load_and_resolve(params["project"])

    skill_folders =
      if connected?(socket),
        do: detect_skill_folders(current_project_id),
        else: []

    slices =
      if connected?(socket),
        do: load_slices(current_project_id),
        else: []

    {:noreply,
     assign(socket,
       projects: projects,
       current_project_id: current_project_id,
       skill_folders: skill_folders,
       slices: slices
     )}
  end

  @impl true
  def handle_info({:session_activity, %{session_id: session_id, status: :started}}, socket) do
    Tracer.with_span "spotter.dashboard.handle_activity",
                     %{attributes: %{"session_id" => session_id, "status" => "started"}} do
      case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
        {:ok, %Session{} = new_session} ->
          sessions =
            [new_session | Enum.reject(socket.assigns.sessions, &(&1.session_id == session_id))]
            |> Enum.sort_by(& &1.started_at, {:desc, DateTime})

          {:noreply, assign(socket, sessions: sessions)}

        _ ->
          {:noreply, socket}
      end
    end
  end

  def handle_info({:session_activity, %{session_id: session_id, status: :finished}}, socket) do
    Tracer.with_span "spotter.dashboard.handle_activity",
                     %{attributes: %{"session_id" => session_id, "status" => "finished"}} do
      {:noreply,
       assign(socket, finished_ids: MapSet.put(socket.assigns.finished_ids, session_id))}
    end
  end

  def handle_info({:session_activity, _}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("refresh", _params, socket) do
    Tracer.with_span "spotter.dashboard.refresh" do
      sessions = load_ongoing_sessions()
      slices = load_slices(socket.assigns.current_project_id)
      {:noreply, assign(socket, sessions: sessions, finished_ids: MapSet.new(), slices: slices)}
    end
  end

  defp detect_skill_folders(nil), do: []

  defp detect_skill_folders(project_id) do
    case SkillFolderReader.detect_folders(project_id) do
      {:ok, folders} -> folders
      _ -> []
    end
  end

  defp load_slices(nil), do: []

  defp load_slices(project_id) do
    Tracer.with_span "spotter.dashboard.load_slices",
                     %{attributes: %{"project_id" => project_id}} do
      case SessionSliceQuery.list_for_project(project_id) do
        {:ok, slices} -> slices
        _ -> []
      end
    end
  end

  defp load_ongoing_sessions do
    Session
    |> Ash.Query.filter(not is_nil(started_at) and is_nil(session_ended_at))
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.read!()
  end

  defp slice_session_label(slice) do
    case slice.session do
      %Session{} = session -> SessionPresenter.primary_label(session)
      _ -> "Unknown session"
    end
  end

  defp slice_session_id(slice) do
    case slice.session do
      %Session{session_id: sid} when is_binary(sid) -> sid
      _ -> nil
    end
  end

  defp slice_ingest_status(slice) do
    case slice.session do
      %Session{ingest_status: status} -> status
      _ -> nil
    end
  end

  defp format_slice_time(nil), do: ""

  defp format_slice_time(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container" data-testid="dashboard-root" id="dashboard-root">
      <div class="page-header">
        <h1>Dashboard</h1>
        <div class="page-header-actions">
          <button class="btn" phx-click="refresh">Refresh</button>
        </div>
      </div>

      <%= if @skill_folders != [] do %>
        <div class="dashboard-cards" data-testid="dashboard-skill-cards">
          <.folder_card :for={folder <- @skill_folders}
            folder={folder}
            project_id={@current_project_id} />
        </div>
      <% end %>

      <%= if @slices != [] do %>
        <div class="dashboard-section" data-testid="dashboard-slices">
          <h2>Saved Slices</h2>
          <div class="dashboard-cards">
            <%= for slice <- @slices do %>
              <% sid = slice_session_id(slice) %>
              <a
                href={if sid, do: "/sessions/#{sid}?slice=#{slice.id}", else: "#"}
                class="dashboard-card"
                data-testid="dashboard-slice-card"
                data-slice-id={slice.id}
              >
                <div class="dashboard-card-label">{slice.title || "Untitled slice"}</div>
                <div class="dashboard-card-path">{slice_session_label(slice)}</div>
                <div class="dashboard-card-count">
                  {length(slice.highlight_tool_use_ids)} highlighted runs
                </div>
                <div class="text-muted text-xs">{format_slice_time(slice.inserted_at)}</div>
                <%= if slice_ingest_status(slice) == :degraded do %>
                  <span class="badge session-status-inactive">degraded</span>
                <% end %>
              </a>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @sessions == [] do %>
        <div class="empty-state">
          No ongoing sessions.
        </div>
      <% else %>
        <table>
          <thead>
            <tr>
              <th>Session</th>
              <th>Project</th>
              <th>Status</th>
              <th>Started</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <%= for session <- @sessions do %>
              <% finished? = MapSet.member?(@finished_ids, session.session_id) %>
              <tr
                data-testid="dashboard-session-row"
                data-session-id={session.session_id}
                class={if finished?, do: "dashboard-row-finished"}
              >
                <td>
                  <div>
                    {SessionPresenter.primary_label(session)}
                    <%= if session.hidden_at do %>
                      <span class="badge session-status-inactive">hidden</span>
                    <% end %>
                  </div>
                  <div class="text-muted text-xs">{SessionPresenter.secondary_label(session)}</div>
                </td>
                <td>{session.cwd || "\u2014"}</td>
                <td>
                  <%= if finished? do %>
                    <span class="badge session-status-ended">finished</span>
                  <% else %>
                    <span class="badge session-status-active">active</span>
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
                <td>
                  <.link navigate={"/sessions/#{session.session_id}"} class="btn btn-success">
                    Review
                  </.link>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end
end
