defmodule SpotterWeb.ReviewsLive do
  use Phoenix.LiveView

  import SpotterWeb.AnnotationComponents, only: [source_badge_text: 1, source_badge_class: 1]

  alias Spotter.Services.ReviewUpdates
  alias Spotter.Transcripts.{Annotation, Project, Session}
  alias Spotter.Transcripts.Sessions
  require Ash.Query
  require OpenTelemetry.Tracer

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       open_annotations: [],
       resolved_annotations: [],
       sessions_by_id: %{},
       projects_by_id: %{},
       delete_target: nil,
       show_confirm_modal: false,
       selection_mode: false,
       selected_ids: MapSet.new(),
       show_image_ann: nil,
       worktree_filter: "all",
       worktree_names: []
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(
       selection_mode: false,
       selected_ids: MapSet.new(),
       delete_target: nil,
       show_confirm_modal: false
     )
     |> load_review_data()}
  end

  @impl true
  def handle_event("delete_annotation", %{"id" => id}, socket) do
    {:noreply, assign(socket, delete_target: id, show_confirm_modal: true)}
  end

  def handle_event("confirm_delete", _params, %{assigns: %{delete_target: :batch}} = socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)
    count = length(ids)

    OpenTelemetry.Tracer.with_span "spotter.reviews.delete_annotation" do
      OpenTelemetry.Tracer.set_attribute("spotter.reviews.delete_type", "batch")
      OpenTelemetry.Tracer.set_attribute("spotter.reviews.count", count)

      Enum.each(ids, fn id ->
        case Ash.get(Annotation, id) do
          {:ok, ann} -> Ash.destroy!(ann)
          _ -> :ok
        end
      end)
    end

    ReviewUpdates.broadcast_counts()

    socket =
      socket
      |> assign(
        selected_ids: MapSet.new(),
        delete_target: nil,
        show_confirm_modal: false,
        selection_mode: false
      )
      |> load_review_data()

    {:noreply, put_flash(socket, :info, "#{count} annotations deleted")}
  end

  def handle_event("confirm_delete", _params, %{assigns: %{delete_target: id}} = socket)
      when is_binary(id) do
    OpenTelemetry.Tracer.with_span "spotter.reviews.delete_annotation" do
      OpenTelemetry.Tracer.set_attribute("spotter.reviews.annotation_id", id)
      OpenTelemetry.Tracer.set_attribute("spotter.reviews.delete_type", "single")

      case Ash.get(Annotation, id) do
        {:ok, ann} -> Ash.destroy!(ann)
        _ -> :ok
      end
    end

    ReviewUpdates.broadcast_counts()

    socket =
      socket
      |> assign(delete_target: nil, show_confirm_modal: false)
      |> load_review_data()

    {:noreply, put_flash(socket, :info, "Annotation deleted")}
  end

  def handle_event("confirm_delete", _params, socket) do
    {:noreply, assign(socket, delete_target: nil, show_confirm_modal: false)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, delete_target: nil, show_confirm_modal: false)}
  end

  def handle_event("enter_selection_mode", _params, socket) do
    {:noreply, assign(socket, selection_mode: true)}
  end

  def handle_event("exit_selection_mode", _params, socket) do
    {:noreply, assign(socket, selection_mode: false, selected_ids: MapSet.new())}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, selected_ids: selected)}
  end

  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, selected_ids: MapSet.new())}
  end

  def handle_event("batch_delete", _params, socket) do
    if MapSet.size(socket.assigns.selected_ids) > 0 do
      {:noreply, assign(socket, delete_target: :batch, show_confirm_modal: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("show_image", %{"id" => id}, socket) do
    {:noreply, assign(socket, show_image_ann: find_annotation(socket, id))}
  end

  def handle_event("close_image", _params, socket) do
    {:noreply, assign(socket, show_image_ann: nil)}
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, delete_target: nil, show_confirm_modal: false, show_image_ann: nil)}
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  def handle_event("filter_worktree", %{"worktree" => value}, socket) do
    {:noreply, socket |> assign(worktree_filter: value) |> load_review_data()}
  end

  defp find_annotation(socket, id) do
    Enum.find(socket.assigns.open_annotations, &(&1.id == id)) ||
      Enum.find(socket.assigns.resolved_annotations, &(&1.id == id))
  end

  defp load_review_data(socket) do
    project_id = socket.assigns.current_project_id

    sessions = load_sessions(project_id)
    session_ids = Enum.map(sessions, & &1.id)
    sessions_by_id = Map.new(sessions, &{&1.id, &1})

    projects_by_id = load_projects_by_id(sessions)

    # Derive canonical project path from any session for worktree detection
    canonical_cwd = derive_canonical_cwd(sessions)

    open_annotations =
      load_review_annotations(session_ids, project_id, :open)
      |> attach_worktree_names(sessions_by_id, canonical_cwd)
      |> filter_by_worktree(socket.assigns.worktree_filter)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Ash.load!([:has_image, :subagent, :file_refs, message_refs: :message])

    resolved_annotations =
      load_review_annotations(session_ids, project_id, :closed)
      |> attach_worktree_names(sessions_by_id, canonical_cwd)
      |> filter_by_worktree(socket.assigns.worktree_filter)
      |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
      |> Ash.load!([:has_image, :subagent, :file_refs, message_refs: :message])

    all_annotations = open_annotations ++ resolved_annotations

    worktree_names =
      all_annotations
      |> Enum.map(& &1.__worktree_name__)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.sort()

    assign(socket,
      open_annotations: open_annotations,
      resolved_annotations: resolved_annotations,
      sessions_by_id: sessions_by_id,
      projects_by_id: projects_by_id,
      worktree_names: worktree_names
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

  defp derive_canonical_cwd(sessions) do
    sessions
    |> Enum.map(& &1.cwd)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Sessions.canonicalize_cwd/1)
    |> Enum.frequencies()
    |> Enum.max_by(fn {_cwd, count} -> count end, fn -> {nil, 0} end)
    |> elem(0)
  end

  defp attach_worktree_names(annotations, sessions_by_id, canonical_cwd) do
    Enum.map(annotations, fn ann ->
      wt_name = resolve_worktree_name(ann, sessions_by_id, canonical_cwd)
      Map.put(ann, :__worktree_name__, wt_name)
    end)
  end

  defp resolve_worktree_name(ann, sessions_by_id, canonical_cwd) do
    case ann.metadata["worktree_name"] do
      wt when is_binary(wt) and wt != "" ->
        wt

      _ ->
        session = Map.get(sessions_by_id, ann.session_id)

        if session && is_binary(session.cwd) && is_binary(canonical_cwd) do
          Sessions.extract_worktree_name(session.cwd, canonical_cwd)
        end
    end
  end

  defp filter_by_worktree(annotations, "all"), do: annotations

  defp filter_by_worktree(annotations, "main"),
    do: Enum.filter(annotations, &is_nil(&1.__worktree_name__))

  defp filter_by_worktree(annotations, wt_name) do
    Enum.filter(annotations, fn ann ->
      ann.__worktree_name__ == wt_name || is_nil(ann.__worktree_name__)
    end)
  end

  defp session_label(session) do
    session.slug || String.slice(session.session_id, 0, 8)
  end

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

    selected = assigns.selection_mode && MapSet.member?(assigns.selected_ids, ann.id)
    sub_label = subagent_label(ann)

    worktree_name = Map.get(ann, :__worktree_name__)

    assigns =
      assigns
      |> assign(
        session: session,
        project: project,
        selected: selected,
        sub_label: sub_label,
        worktree_name: worktree_name
      )

    ~H"""
    <div class={["annotation-card", @selected && "border-[var(--accent-blue)] bg-[color-mix(in_srgb,var(--accent-blue)_4%,transparent)]"]} data-testid={"annotation-card-#{@ann.id}"}>
      <div class="flex items-center gap-2 mb-2">
        <input
          :if={@selection_mode}
          type="checkbox"
          class="w-4 h-4 rounded border-[var(--border-default)] bg-[var(--surface-1)] checked:bg-[var(--accent-blue)] cursor-pointer"
          checked={@selected}
          phx-click="toggle_select"
          phx-value-id={@ann.id}
        />
        <span class={source_badge_class(@ann.source)}>
          {source_badge_text(@ann.source)}
        </span>
        <span :if={@ann.source == :transcript && @ann.message_refs != []} class="text-muted text-xs">
          {length(@ann.message_refs)} messages
        </span>
        <span :if={@worktree_name} class="badge text-xs px-1.5 py-0.5 rounded bg-[color-mix(in_srgb,var(--accent-purple)_15%,transparent)] text-[var(--accent-purple)] border border-[color-mix(in_srgb,var(--accent-purple)_30%,transparent)]">
          {@worktree_name}
        </span>
        <span :if={@project} class="text-muted text-xs">
          {@project.name}
        </span>
        <span :if={@session} class="text-muted text-xs">
          {session_label(@session)}
        </span>
        <%= if @sub_label do %>
          <span class="badge badge-agent">Subagent</span>
          <span class="text-muted text-xs">{@sub_label}</span>
        <% else %>
          <%= if @ann.subagent_id do %>
            <span class="badge badge-agent">Subagent (missing)</span>
          <% end %>
        <% end %>
      </div>
      <pre class="annotation-text"><%= @ann.selected_text %></pre>
      <p class="annotation-comment"><%= @ann.comment %></p>
      <div :if={@ann.has_image} class="annotation-thumbnail-wrap" data-testid="annotation-thumbnail">
        <img
          src={"/api/annotations/#{@ann.id}/image"}
          alt="Annotation screenshot"
          class="annotation-thumbnail"
          loading="lazy"
          phx-click="show_image"
          phx-value-id={@ann.id}
        />
      </div>
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
        <button :if={!@selection_mode} class="btn-ghost text-error text-xs ml-auto" phx-click="delete_annotation" phx-value-id={@ann.id}>
          Delete
        </button>
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

  defp confirm_modal(assigns) do
    ~H"""
    <div :if={@show_confirm_modal} class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center" phx-click="cancel_delete" phx-window-keydown="keydown">
      <div class="bg-[var(--surface-1)] border border-[var(--border-default)] rounded-lg p-6 max-w-[400px] w-full mx-4" phx-click-away="cancel_delete">
        <h3 class="text-[var(--text-primary)] font-semibold text-base">
          <%= if @delete_target == :batch do %>
            Delete <%= MapSet.size(@selected_ids) %> annotations?
          <% else %>
            Delete this annotation?
          <% end %>
        </h3>
        <p class="text-[var(--text-secondary)] text-sm mt-2">This action cannot be undone.</p>
        <div class="flex justify-end gap-3 mt-6">
          <button class="btn" phx-click="cancel_delete">Cancel</button>
          <button class="btn btn-error" phx-click="confirm_delete">
            <%= if @delete_target == :batch, do: "Delete all", else: "Delete" %>
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp batch_action_bar(assigns) do
    ~H"""
    <div :if={@selection_mode and MapSet.size(@selected_ids) > 0}
         class="fixed bottom-0 left-[200px] right-0 bg-[var(--surface-1)] border-t border-[var(--border-default)] px-4 py-3 flex items-center justify-between shadow-[0_-2px_8px_rgba(0,0,0,0.2)] z-40">
      <span class="text-[var(--text-secondary)] text-sm">
        {MapSet.size(@selected_ids)} selected
      </span>
      <div class="flex items-center gap-3">
        <button class="btn btn-ghost btn-sm" phx-click="deselect_all">Clear selection</button>
        <button class="btn btn-error btn-sm" phx-click="batch_delete">Delete selected</button>
      </div>
    </div>
    """
  end

  defp image_modal(assigns) do
    metadata = (assigns.ann && assigns.ann.metadata) || %{}

    feedback_meta =
      for {"feedback." <> label, value} <- metadata do
        {label, value}
      end
      |> Enum.sort()

    assigns = assign(assigns, feedback_meta: feedback_meta)

    ~H"""
    <div
      :if={@ann}
      class="image-modal-overlay"
      phx-window-keydown="keydown"
      data-testid="image-modal"
    >
      <div class="image-modal-content" phx-click-away="close_image">
        <div class="image-modal-header">
          <span class="text-sm text-[var(--text-primary)]">Screenshot</span>
          <button class="btn-ghost text-xs" phx-click="close_image" data-testid="image-modal-close">&times;</button>
        </div>
        <img
          src={"/api/annotations/#{@ann.id}/image"}
          alt="Annotation screenshot"
          class="image-modal-img"
          data-testid="image-modal-img"
        />
        <div :if={@feedback_meta != []} class="image-modal-meta" data-testid="image-modal-metadata">
          <div :for={{label, value} <- @feedback_meta} class="image-modal-meta-row" data-testid={"image-meta-#{String.replace(label, "_", "-")}"}>
            <span class="image-modal-meta-label">{label}</span>
            <span class="image-modal-meta-value">{value}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container" data-testid="reviews-root">
      <div class="page-header flex items-center justify-between">
        <h1>Reviews</h1>
        <%= if @current_project_id do %>
          <button :if={!@selection_mode} class="btn btn-ghost btn-sm" phx-click="enter_selection_mode">
            Select
          </button>
          <button :if={@selection_mode} class="btn btn-ghost btn-sm" phx-click="exit_selection_mode">
            Cancel
          </button>
        <% end %>
      </div>

      <div :if={Phoenix.Flash.get(@flash, :info)} class="flash-info">
        {Phoenix.Flash.get(@flash, :info)}
      </div>

      <div :if={Phoenix.Flash.get(@flash, :error)} class="flash-error">
        {Phoenix.Flash.get(@flash, :error)}
      </div>

      <%= if @current_project_id do %>
        <div class="review-header flex items-center gap-4">
          <span class="review-count">
            {length(@open_annotations)} open annotations
          </span>
          <form :if={@worktree_names != []} phx-change="filter_worktree" class="ml-auto">
            <select name="worktree" class="select select-sm bg-[var(--surface-1)] border-[var(--border-default)] text-[var(--text-primary)]">
              <option value="all" selected={@worktree_filter == "all"}>All worktrees</option>
              <option value="main" selected={@worktree_filter == "main"}>Main</option>
              <option :for={wt <- @worktree_names} value={wt} selected={@worktree_filter == wt}>{wt}</option>
            </select>
          </form>
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
            <.annotation_card ann={ann} sessions_by_id={@sessions_by_id} projects_by_id={@projects_by_id} selection_mode={@selection_mode} selected_ids={@selected_ids} />
          <% end %>
        <% end %>

        <%= if @resolved_annotations != [] do %>
          <div class="resolved-section" data-testid="resolved-section">
            <h3 class="resolved-heading">
              Resolved annotations
              <span class="text-muted">({length(@resolved_annotations)})</span>
            </h3>
            <%= for ann <- @resolved_annotations do %>
              <.annotation_card ann={ann} sessions_by_id={@sessions_by_id} projects_by_id={@projects_by_id} selection_mode={@selection_mode} selected_ids={@selected_ids} />
            <% end %>
          </div>
        <% end %>
      <% else %>
        <div class="empty-state">
          No project selected.
        </div>
      <% end %>
    </div>

    <.confirm_modal show_confirm_modal={@show_confirm_modal} delete_target={@delete_target} selected_ids={@selected_ids} />
    <.batch_action_bar selection_mode={@selection_mode} selected_ids={@selected_ids} />
    <.image_modal ann={@show_image_ann} />
    """
  end
end
