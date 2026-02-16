defmodule SpotterWeb.ReviewsLive do
  use Phoenix.LiveView

  alias Spotter.Services.{
    ReviewCounts,
    ReviewUpdates
  }

  alias Spotter.Transcripts.{Annotation, Project, Session}
  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    project_counts = ReviewCounts.list_project_open_counts()

    {:ok,
     socket
     |> assign(
       project_counts: project_counts,
       selected_project_id: nil,
       open_annotations: [],
       resolved_annotations: [],
       sessions_by_id: %{},
       projects_by_id: %{}
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
        |> Ash.Query.filter(session_id in ^session_ids and state == :open and purpose == :review)
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
        |> Ash.Query.filter(session_id in ^session_ids and state == :open and purpose == :review)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.read!()
        |> Ash.load!([:subagent, :file_refs, message_refs: :message])
      end

    resolved_annotations =
      if session_ids == [] || project_id == nil do
        []
      else
        Annotation
        |> Ash.Query.filter(
          session_id in ^session_ids and state == :closed and purpose == :review
        )
        |> Ash.Query.sort(updated_at: :desc)
        |> Ash.read!()
        |> Ash.load!([:subagent, :file_refs, message_refs: :message])
      end

    assign(socket,
      open_annotations: open_annotations,
      resolved_annotations: resolved_annotations,
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
  defp source_badge(:file), do: "File"
  defp source_badge(_), do: "Terminal"

  defp source_badge_class(:transcript), do: "badge badge-agent"
  defp source_badge_class(:file), do: "badge badge-verified"
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
      <%= if @ann.state == :closed do %>
        <.resolution_block ann={@ann} />
      <% end %>
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

  defp resolution_block(assigns) do
    metadata = assigns.ann.metadata || %{}

    assigns =
      assign(assigns,
        resolution: metadata["resolution"],
        resolution_kind: metadata["resolution_kind"],
        resolved_at: parse_resolved_at(metadata["resolved_at"])
      )

    ~H"""
    <div class="resolution-block">
      <span class="resolution-label">Resolution note:</span>
      <%= if @resolution && @resolution != "" do %>
        <span class="resolution-text">{@resolution}</span>
      <% else %>
        <span class="resolution-text text-muted">(missing)</span>
      <% end %>
      <span :if={@resolution_kind} class="badge badge-muted">{@resolution_kind}</span>
      <span :if={@resolved_at} class="text-muted text-xs">
        {Calendar.strftime(@resolved_at, "%Y-%m-%d %H:%M")}
      </span>
    </div>
    """
  end

  defp parse_resolved_at(nil), do: nil

  defp parse_resolved_at(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_resolved_at(_), do: nil

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
            <button class="btn btn-danger" phx-click="close_review_session">
              Close review session
            </button>
          </div>
        </div>

        <div class="instruction-panel" data-testid="mcp-review-instructions">
          <h3>Run this review in Claude Code</h3>
          <ol>
            <li>Ensure MCP server "spotter" is enabled (worktrees generate .mcp.json).</li>
            <li>In Claude Code, run the Spotter review skill: "spotter-review".</li>
            <li>Resolve each annotation using the skill; Spotter will update counts automatically.</li>
          </ol>
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

        <%= if @resolved_annotations != [] do %>
          <div class="resolved-section" data-testid="resolved-section">
            <h3 class="resolved-heading">
              Resolved annotations
              <span class="text-muted">({length(@resolved_annotations)})</span>
            </h3>
            <%= for ann <- @resolved_annotations do %>
              <.annotation_card ann={ann} sessions_by_id={@sessions_by_id} projects_by_id={@projects_by_id} />
            <% end %>
          </div>
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
