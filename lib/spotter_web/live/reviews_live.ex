defmodule SpotterWeb.ReviewsLive do
  use Phoenix.LiveView

  alias Spotter.Services.{
    ReviewCounts,
    ReviewSessionRegistry,
    ReviewTokenStore,
    ReviewUpdates,
    Tmux
  }

  alias Spotter.Transcripts.{Annotation, Project, Session}
  require Ash.Query

  @review_port Application.compile_env(:spotter, [SpotterWeb.Endpoint, :http, :port], 1100)
  @review_heartbeat_interval 10_000

  @impl true
  def mount(_params, _session, socket) do
    project_counts = ReviewCounts.list_project_open_counts()

    {:ok,
     socket
     |> assign(
       project_counts: project_counts,
       selected_project_id: nil,
       open_annotations: [],
       sessions_by_id: %{},
       projects_by_id: %{},
       review_session_name: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = parse_project_id(params["project_id"])

    socket =
      socket
      |> assign(selected_project_id: project_id)
      |> load_review_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = parse_project_id(raw_id)
    path = if project_id, do: "/reviews?project_id=#{project_id}", else: "/reviews"

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("close_review_session", _params, socket) do
    project_id = socket.assigns.selected_project_id

    sessions =
      Session
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.Query.select([:id])
      |> Ash.read!()

    session_ids = Enum.map(sessions, & &1.id)

    closed_count =
      if session_ids == [] do
        0
      else
        Annotation
        |> Ash.Query.filter(session_id in ^session_ids and state == :open)
        |> Ash.read!()
        |> Enum.reduce(0, fn ann, acc ->
          Ash.update!(ann, %{}, action: :close)
          acc + 1
        end)
      end

    if closed_count > 0, do: ReviewUpdates.broadcast_counts()

    {:noreply,
     socket
     |> assign(project_counts: ReviewCounts.list_project_open_counts())
     |> put_flash(:info, "Closed #{closed_count} annotations")
     |> load_review_data()}
  end

  def handle_event("open_conversation", _params, socket) do
    project_id = socket.assigns.selected_project_id
    token = ReviewTokenStore.mint(project_id)

    case tmux_module().launch_project_review(project_id, token, @review_port) do
      {:ok, name} ->
        previous = socket.assigns.review_session_name

        if previous && previous != name do
          ReviewSessionRegistry.deregister(previous)
        end

        ReviewSessionRegistry.register(name)
        Process.send_after(self(), :review_heartbeat, @review_heartbeat_interval)

        {:noreply,
         socket
         |> assign(review_session_name: name)
         |> put_flash(:info, "Launched review session: #{name}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :info, "Failed to launch: #{reason}")}
    end
  end

  @impl true
  def handle_info(:review_heartbeat, socket) do
    if name = socket.assigns.review_session_name do
      ReviewSessionRegistry.heartbeat(name)
      Process.send_after(self(), :review_heartbeat, @review_heartbeat_interval)
    end

    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if name = socket.assigns[:review_session_name] do
      ReviewSessionRegistry.deregister(name)
    end

    :ok
  end

  defp tmux_module, do: Application.get_env(:spotter, :tmux_module, Tmux)

  defp parse_project_id("all"), do: nil
  defp parse_project_id(nil), do: nil
  defp parse_project_id(""), do: nil

  defp parse_project_id(id) do
    case Ash.get(Project, id) do
      {:ok, _} -> id
      _ -> nil
    end
  end

  defp load_review_data(socket) do
    project_id = socket.assigns.selected_project_id

    sessions = load_sessions(project_id)
    session_ids = Enum.map(sessions, & &1.id)
    sessions_by_id = Map.new(sessions, &{&1.id, &1})

    project_ids = sessions |> Enum.map(& &1.project_id) |> Enum.uniq()

    projects_by_id =
      if project_ids == [] do
        %{}
      else
        Project
        |> Ash.Query.filter(id in ^project_ids)
        |> Ash.read!()
        |> Map.new(&{&1.id, &1})
      end

    open_annotations =
      if session_ids == [] do
        []
      else
        Annotation
        |> Ash.Query.filter(session_id in ^session_ids and state == :open)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.read!()
        |> Ash.load!([:subagent, message_refs: :message])
      end

    assign(socket,
      open_annotations: open_annotations,
      sessions_by_id: sessions_by_id,
      projects_by_id: projects_by_id
    )
  end

  defp load_sessions(nil) do
    Session
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.read!()
  end

  defp load_sessions(project_id) do
    Session
    |> Ash.Query.filter(project_id == ^project_id)
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.read!()
  end

  defp total_open_count(project_counts) do
    Enum.sum(Enum.map(project_counts, & &1.open_count))
  end

  defp session_label(session) do
    session.slug || String.slice(session.session_id, 0, 8)
  end

  defp source_badge(:transcript), do: "Transcript"
  defp source_badge(_), do: "Terminal"

  defp source_badge_class(:transcript), do: "badge badge-agent"
  defp source_badge_class(_), do: "badge badge-terminal"

  defp subagent_label(%{subagent: %{slug: slug}} = _ann) when is_binary(slug), do: slug
  defp subagent_label(%{subagent: %{agent_id: aid}}), do: String.slice(aid, 0, 8)
  defp subagent_label(_), do: nil

  defp annotation_link(ann, session) do
    case {ann.subagent_id, ann.subagent, session} do
      {nil, _, %{session_id: sid}} -> "/sessions/#{sid}"
      {_, %{agent_id: aid}, %{session_id: sid}} -> "/sessions/#{sid}/agents/#{aid}"
      {_, _, %{session_id: sid}} -> "/sessions/#{sid}"
      _ -> "#"
    end
  end

  defp annotations_for_project(project_id, annotations, sessions_by_id) do
    Enum.filter(annotations, fn ann ->
      case Map.get(sessions_by_id, ann.session_id) do
        %{project_id: ^project_id} -> true
        _ -> false
      end
    end)
  end

  defp annotation_card(assigns) do
    ann = assigns.ann
    session = Map.get(assigns.sessions_by_id, ann.session_id)
    project = session && Map.get(assigns.projects_by_id, session.project_id)

    assigns =
      assigns
      |> assign(session: session, project: project)

    ~H"""
    <div class="annotation-card">
      <div class="flex items-center gap-2 mb-2">
        <span class={source_badge_class(@ann.source)}>
          {source_badge(@ann.source)}
        </span>
        <span :if={@ann.source == :transcript && @ann.message_refs != []} class="text-muted text-xs">
          {length(@ann.message_refs)} messages
        </span>
        <span :if={@project} class="text-muted text-xs">
          {@project.name}
        </span>
        <span :if={@session} class="text-muted text-xs">
          {session_label(@session)}
        </span>
        <%= if subagent_label(@ann) do %>
          <span class="badge badge-agent">Subagent</span>
          <span class="text-muted text-xs">{subagent_label(@ann)}</span>
        <% else %>
          <%= if @ann.subagent_id do %>
            <span class="badge badge-agent">Subagent (missing)</span>
          <% end %>
        <% end %>
      </div>
      <pre class="annotation-text"><%= @ann.selected_text %></pre>
      <p class="annotation-comment"><%= @ann.comment %></p>
      <div class="annotation-meta">
        <span class="annotation-time">
          <%= Calendar.strftime(@ann.inserted_at, "%H:%M") %>
        </span>
        <a :if={@session} href={annotation_link(@ann, @session)} class="text-xs">
          <%= if @ann.subagent_id && @ann.subagent, do: "View agent", else: "View session" %>
        </a>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container" data-testid="reviews-root">
      <div class="page-header">
        <h1>Reviews</h1>
      </div>

      <div :if={Phoenix.Flash.get(@flash, :info)} class="flash-info">
        {Phoenix.Flash.get(@flash, :info)}
      </div>

      <div :if={Phoenix.Flash.get(@flash, :error)} class="flash-error">
        {Phoenix.Flash.get(@flash, :error)}
      </div>

      <div class="filter-section">
        <div>
          <label class="filter-label">Project</label>
          <div class="filter-bar">
            <button
              phx-click="filter_project"
              phx-value-project-id="all"
              class={"filter-btn#{if @selected_project_id == nil, do: " is-active"}"}
            >
              All ({total_open_count(@project_counts)})
            </button>
            <button
              :for={pc <- @project_counts}
              phx-click="filter_project"
              phx-value-project-id={pc.project_id}
              class={"filter-btn#{if @selected_project_id == pc.project_id, do: " is-active"}"}
            >
              {pc.project_name} ({pc.open_count})
            </button>
          </div>
        </div>
      </div>

      <%= if @selected_project_id do %>
        <div class="review-header">
          <span class="review-count">
            {length(@open_annotations)} open annotations
          </span>
          <div class="review-actions">
            <button class="btn btn-success" phx-click="open_conversation">
              Open conversation
            </button>
            <button class="btn btn-danger" phx-click="close_review_session">
              Close review session
            </button>
          </div>
        </div>

        <%= if @open_annotations == [] do %>
          <div class="empty-state">
            No open annotations for the selected scope.
          </div>
        <% else %>
          <%= for ann <- @open_annotations do %>
            <.annotation_card ann={ann} sessions_by_id={@sessions_by_id} projects_by_id={@projects_by_id} />
          <% end %>
        <% end %>
      <% else %>
        <%= for pc <- @project_counts do %>
          <% project_annotations = annotations_for_project(pc.project_id, @open_annotations, @sessions_by_id) %>
          <div class="project-section">
            <div class="project-header">
              <span class="project-name">{pc.project_name}</span>
              <span class="project-count">({pc.open_count} open)</span>
            </div>
            <%= if project_annotations == [] do %>
              <div class="text-muted text-sm">No open annotations.</div>
            <% else %>
              <%= for ann <- project_annotations do %>
                <.annotation_card ann={ann} sessions_by_id={@sessions_by_id} projects_by_id={@projects_by_id} />
              <% end %>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
