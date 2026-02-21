defmodule SpotterWeb.ProjectReviewLive do
  use Phoenix.LiveView

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
      load_review_annotations(session_ids, project.id, :open)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Ash.load!([:subagent, message_refs: :message])

    resolved_annotations =
      load_review_annotations(session_ids, project.id, :closed)
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
      |> Ash.load!([:subagent, message_refs: :message])

    assign(socket,
      sessions: sessions,
      sessions_by_id: sessions_by_id,
      open_annotations: open_annotations,
      resolved_annotations: resolved_annotations
    )
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
      Annotation
      |> Ash.Query.filter(
        is_nil(session_id) and project_id == ^project_id and state == ^state and
          purpose == :review
      )
      |> Ash.read!()

    session_bound ++ unbound
  end

  defp session_label(session) do
    session.slug || String.slice(session.session_id, 0, 8)
  end

  defp source_badge(:transcript), do: "Transcript"
  defp source_badge(_), do: "Transcript"

  defp source_badge_class(:transcript), do: "badge badge-agent"
  defp source_badge_class(_), do: "badge badge-agent"

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
            No open annotations for this project.
          </div>
        <% else %>
          <div class="review-header">
            <span class="review-count">
              {length(@open_annotations)} open annotations across {map_size(@sessions_by_id)} sessions
            </span>
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
