defmodule SpotterWeb.ProjectReviewLive do
  use Phoenix.LiveView

  alias Spotter.Services.ReviewUpdates
  alias Spotter.Transcripts.{Annotation, Project, Session}
  require Ash.Query

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    case Ash.get(Project, project_id) do
      {:ok, project} ->
        {:ok,
         socket
         |> assign(project: project)
         |> load_review_data()}

      _ ->
        {:ok,
         assign(socket,
           project: nil,
           sessions: [],
           open_annotations: [],
           resolved_annotations: []
         )}
    end
  end

  @impl true
  def handle_event("close_review_session", _params, socket) do
    project = socket.assigns.project

    sessions =
      Session
      |> Ash.Query.filter(project_id == ^project.id)
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
     |> put_flash(:info, "Closed #{closed_count} annotations")
     |> load_review_data()}
  end

  defp load_review_data(socket) do
    project = socket.assigns.project

    sessions =
      Session
      |> Ash.Query.filter(project_id == ^project.id)
      |> Ash.Query.sort(started_at: :desc)
      |> Ash.read!()

    session_ids = Enum.map(sessions, & &1.id)
    sessions_by_id = Map.new(sessions, &{&1.id, &1})

    open_annotations =
      if session_ids == [] do
        []
      else
        Annotation
        |> Ash.Query.filter(session_id in ^session_ids and state == :open and purpose == :review)
        |> Ash.Query.sort(inserted_at: :desc)
        |> Ash.read!()
        |> Ash.load!([:subagent, message_refs: :message])
      end

    resolved_annotations =
      if session_ids == [] do
        []
      else
        Annotation
        |> Ash.Query.filter(
          session_id in ^session_ids and state == :closed and purpose == :review
        )
        |> Ash.Query.sort(updated_at: :desc)
        |> Ash.read!()
        |> Ash.load!([:subagent, message_refs: :message])
      end

    assign(socket,
      sessions: sessions,
      sessions_by_id: sessions_by_id,
      open_annotations: open_annotations,
      resolved_annotations: resolved_annotations
    )
  end

  defp session_label(session) do
    session.slug || String.slice(session.session_id, 0, 8)
  end

  defp source_badge(:transcript), do: "Transcript"
  defp source_badge(_), do: "Terminal"

  defp source_badge_class(:transcript), do: "badge badge-agent"
  defp source_badge_class(_), do: "badge badge-terminal"

  defp subagent_label(%{subagent: %{slug: slug}}) when is_binary(slug), do: slug
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
    <div class="container">
      <div class="breadcrumb">
        <a href="/">Dashboard</a>
        <span class="breadcrumb-sep">/</span>
        <span class="breadcrumb-current">
          <%= if @project, do: "Review: #{@project.name}", else: "Project not found" %>
        </span>
      </div>

      <div :if={Phoenix.Flash.get(@flash, :info)} class="flash-info">
        {Phoenix.Flash.get(@flash, :info)}
      </div>

      <div :if={Phoenix.Flash.get(@flash, :error)} class="flash-error">
        {Phoenix.Flash.get(@flash, :error)}
      </div>

      <%= if is_nil(@project) do %>
        <div class="empty-state">
          The requested project does not exist.
        </div>
      <% else %>
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
            No open annotations for this project.
          </div>
        <% else %>
          <div class="review-header">
            <span class="review-count">
              {length(@open_annotations)} open annotations across {map_size(@sessions_by_id)} sessions
            </span>
            <div class="review-actions">
              <button class="btn btn-danger" phx-click="close_review_session">
                Close review session
              </button>
            </div>
          </div>

          <%= for ann <- @open_annotations do %>
            <% session = Map.get(@sessions_by_id, ann.session_id) %>
            <div class="annotation-card">
              <div class="flex items-center gap-2 mb-2">
                <span class={source_badge_class(ann.source)}>
                  {source_badge(ann.source)}
                </span>
                <span :if={ann.source == :transcript && ann.message_refs != []} class="text-muted text-xs">
                  {length(ann.message_refs)} messages
                </span>
                <span :if={session} class="text-muted text-xs">
                  {session_label(session)}
                </span>
                <%= if subagent_label(ann) do %>
                  <span class="badge badge-agent">Subagent</span>
                  <span class="text-muted text-xs">{subagent_label(ann)}</span>
                <% else %>
                  <%= if ann.subagent_id do %>
                    <span class="badge badge-agent">Subagent (missing)</span>
                  <% end %>
                <% end %>
              </div>
              <pre class="annotation-text"><%= ann.selected_text %></pre>
              <p class="annotation-comment"><%= ann.comment %></p>
              <div class="annotation-meta">
                <span class="annotation-time">
                  <%= Calendar.strftime(ann.inserted_at, "%H:%M") %>
                </span>
                <a :if={session} href={annotation_link(ann, session)} class="text-xs">
                  <%= if ann.subagent_id && ann.subagent, do: "View agent", else: "View session" %>
                </a>
              </div>
            </div>
          <% end %>
        <% end %>

        <%= if @resolved_annotations != [] do %>
          <div class="resolved-section" data-testid="resolved-section">
            <h3 class="resolved-heading">
              Resolved annotations
              <span class="text-muted">({length(@resolved_annotations)})</span>
            </h3>
            <%= for ann <- @resolved_annotations do %>
              <% session = Map.get(@sessions_by_id, ann.session_id) %>
              <div class="annotation-card">
                <div class="flex items-center gap-2 mb-2">
                  <span class={source_badge_class(ann.source)}>
                    {source_badge(ann.source)}
                  </span>
                  <span :if={ann.source == :transcript && ann.message_refs != []} class="text-muted text-xs">
                    {length(ann.message_refs)} messages
                  </span>
                  <span :if={session} class="text-muted text-xs">
                    {session_label(session)}
                  </span>
                  <%= if subagent_label(ann) do %>
                    <span class="badge badge-agent">Subagent</span>
                    <span class="text-muted text-xs">{subagent_label(ann)}</span>
                  <% else %>
                    <%= if ann.subagent_id do %>
                      <span class="badge badge-agent">Subagent (missing)</span>
                    <% end %>
                  <% end %>
                </div>
                <pre class="annotation-text"><%= ann.selected_text %></pre>
                <p class="annotation-comment"><%= ann.comment %></p>
                <.resolution_block ann={ann} />
                <div class="annotation-meta">
                  <span class="annotation-time">
                    <%= Calendar.strftime(ann.inserted_at, "%H:%M") %>
                  </span>
                  <a :if={session} href={annotation_link(ann, session)} class="text-xs">
                    <%= if ann.subagent_id && ann.subagent, do: "View agent", else: "View session" %>
                  </a>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
