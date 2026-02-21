defmodule SpotterWeb.ReviewsLive do
  use Phoenix.LiveView

  alias Spotter.Services.ReviewCounts

  alias Spotter.Transcripts.{Annotation, Project, Session}
  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    project_counts = ReviewCounts.list_project_open_counts()

    {:ok,
     socket
     |> assign(
       project_counts: project_counts,
       selected_project_id: first_project_id(project_counts),
       open_annotations: [],
       resolved_annotations: [],
       sessions_by_id: %{},
       projects_by_id: %{}
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id =
      normalize_project_id(socket.assigns.project_counts, parse_project_id(params["project_id"]))

    socket =
      socket
      |> assign(selected_project_id: project_id)
      |> load_review_data()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = normalize_project_id(socket.assigns.project_counts, parse_project_id(raw_id))
    path = if project_id, do: "/reviews?project_id=#{project_id}", else: "/reviews"

    {:noreply, push_patch(socket, to: path)}
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

  defp first_project_id(project_counts) do
    List.first(project_counts) |> then(&(&1 && &1.project_id))
  end

  defp normalize_project_id(project_counts, project_id) do
    first = first_project_id(project_counts)

    case project_id do
      nil -> first
      _ -> if project_exists?(project_counts, project_id), do: project_id, else: first
    end
  end

  defp project_exists?(project_counts, project_id) do
    Enum.any?(project_counts, &(&1.project_id == project_id))
  end

  defp load_review_data(socket) do
    project_id = socket.assigns.selected_project_id

    sessions = load_sessions(project_id)
    session_ids = Enum.map(sessions, & &1.id)
    sessions_by_id = Map.new(sessions, &{&1.id, &1})

    projects_by_id = load_projects_by_id(sessions)

    open_annotations =
      load_review_annotations(session_ids, project_id, :open)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Ash.load!([:subagent, :file_refs, message_refs: :message])

    resolved_annotations =
      load_review_annotations(session_ids, project_id, :closed)
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
      |> Ash.load!([:subagent, :file_refs, message_refs: :message])

    assign(socket,
      open_annotations: open_annotations,
      resolved_annotations: resolved_annotations,
      sessions_by_id: sessions_by_id,
      projects_by_id: projects_by_id
    )
  end

  defp load_projects_by_id(sessions) do
    project_ids = sessions |> Enum.map(& &1.project_id) |> Enum.uniq()

    if project_ids == [] do
      %{}
    else
      Project
      |> Ash.Query.filter(id in ^project_ids)
      |> Ash.read!()
      |> Map.new(&{&1.id, &1})
    end
  end

  defp load_review_annotations(session_ids, project_id, state) do
    session_bound =
      if session_ids == [] do
        []
      else
        Annotation
        |> Ash.Query.filter(session_id in ^session_ids and state == ^state and purpose == :review)
        |> Ash.read!()
      end

    unbound =
      if project_id do
        Annotation
        |> Ash.Query.filter(
          is_nil(session_id) and project_id == ^project_id and state == ^state and
            purpose == :review
        )
        |> Ash.read!()
      else
        []
      end

    session_bound ++ unbound
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

  defp session_label(session) do
    session.slug || String.slice(session.session_id, 0, 8)
  end

  defp source_badge(:transcript), do: "Transcript"
  defp source_badge(:file), do: "File"
  defp source_badge(:prompt_pattern), do: "Pattern"
  defp source_badge(_), do: "Transcript"

  defp source_badge_class(:transcript), do: "badge badge-agent"
  defp source_badge_class(:file), do: "badge badge-verified"
  defp source_badge_class(:prompt_pattern), do: "badge badge-pattern"
  defp source_badge_class(_), do: "badge badge-agent"

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
        </div>

        <div class="instruction-panel" data-testid="mcp-review-instructions">
          <h3 class="instruction-panel-heading">Review in Claude Code</h3>
          <div class="instruction-panel-sections">
            <div class="instruction-panel-section">
              <h4 class="instruction-panel-label">Setup</h4>
              <p>The Spotter plugin provides the MCP server automatically. Verify it's active: run <code>/mcp</code> in Claude Code and check that <code>spotter</code> appears in the server list.</p>
            </div>
            <div class="instruction-panel-section">
              <h4 class="instruction-panel-label">Run review</h4>
              <p>Type <code>/spotter-review</code> in Claude Code. The skill lists sessions, fetches open annotations, and guides you through resolving each one.</p>
            </div>
            <div class="instruction-panel-section">
              <h4 class="instruction-panel-label">Review modes</h4>
              <ul class="instruction-panel-modes">
                <li><code>/spotter-review</code> Full guided review</li>
                <li><code>/spotter-review-one-by-one</code> Resolve one at a time</li>
                <li><code>/spotter-review-batch</code> Batch resolve by file/topic</li>
              </ul>
            </div>
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
        <div class="empty-state">
          No project selected.
        </div>
      <% end %>
    </div>
    """
  end
end
