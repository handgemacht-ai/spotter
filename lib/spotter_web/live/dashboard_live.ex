defmodule SpotterWeb.DashboardLive do
  use Phoenix.LiveView

  alias Spotter.Transcripts.{Session, SessionPresenter}

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

      {:ok, socket}
    end
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
      {:noreply, assign(socket, sessions: sessions, finished_ids: MapSet.new())}
    end
  end

  defp load_ongoing_sessions do
    Session
    |> Ash.Query.filter(not is_nil(started_at) and is_nil(session_ended_at))
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.read!()
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
