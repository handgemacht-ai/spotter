defmodule SpotterWeb.SessionLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  require Logger

  import SpotterWeb.TranscriptComponents
  import SpotterWeb.AnnotationComponents

  alias Spotter.Services.{
    ExplainAnnotations,
    ReviewSessionRegistry,
    ReviewUpdates,
    SessionRegistry,
    Tmux,
    TranscriptFileLinks,
    TranscriptSync
  }

  alias Spotter.Transcripts.{
    Annotation,
    AnnotationMessageRef,
    Commit,
    Jobs.SyncTranscripts,
    Message,
    Session,
    SessionCommitLink,
    SessionRework,
    Subagent,
    ToolCall
  }

  require Ash.Query

  attach_computer(SpotterWeb.Live.TranscriptComputers, :transcript_view)

  @review_heartbeat_interval 10_000

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    {pane_id, review_session_name} = find_pane_with_review_info(session_id)

    {cols, rows} = pane_dimensions(pane_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Spotter.PubSub, "pane_sessions")
      Phoenix.PubSub.subscribe(Spotter.PubSub, "session_activity")
      Phoenix.PubSub.subscribe(Spotter.PubSub, "session_transcripts:#{session_id}")

      if is_nil(pane_id) do
        Process.send_after(self(), :check_pane, 1_000)
      end

      if review_session_name do
        ReviewSessionRegistry.register(review_session_name)
        Process.send_after(self(), :review_heartbeat, @review_heartbeat_interval)
      end
    end

    {session_record, messages} = load_session_data(session_id)
    annotations = load_annotations(session_record)
    errors = load_errors(session_record)
    rework_events = load_rework_events(session_record)
    commit_links = load_commit_links(session_id)
    subagent_labels = load_subagent_labels(session_record)
    session_cwd = if session_record, do: session_record.cwd, else: nil
    {link_project_id, link_fileset} = resolve_file_link_context(session_record)

    socket =
      socket
      |> assign(
        pane_id: pane_id,
        session_id: session_id,
        session_status: nil,
        session_record: session_record,
        review_session_name: review_session_name,
        cols: cols,
        rows: rows,
        annotations: annotations,
        selected_text: nil,
        selection_source: nil,
        selection_message_ids: [],
        selection_start_row: nil,
        selection_start_col: nil,
        selection_end_row: nil,
        selection_end_col: nil,
        errors: errors,
        rework_events: rework_events,
        commit_links: commit_links,
        subagent_labels: subagent_labels,
        current_message_id: nil,
        show_transcript: true,
        clicked_subagent: nil,
        active_sidebar_tab: :commits,
        explain_streams: %{},
        transcript_link_project_id: link_project_id,
        transcript_link_fileset: link_fileset
      )
      |> mount_computers(%{
        transcript_view: %{messages: messages, session_cwd: session_cwd}
      })

    rendered_lines = socket.assigns.transcript_view_rendered_lines
    {breakpoint_map, anchors} = compute_sync_data(pane_id, rendered_lines)

    socket =
      socket
      |> assign(breakpoint_map: breakpoint_map, anchors: anchors)
      |> push_sync_events()

    {:ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if name = socket.assigns[:review_session_name] do
      ReviewSessionRegistry.deregister(name)
    end

    :ok
  end

  @impl true
  def handle_info(:check_pane, socket) do
    case find_pane_with_review_info(socket.assigns.session_id) do
      {nil, _} ->
        Process.send_after(self(), :check_pane, 1_000)
        {:noreply, socket}

      {pane_id, review_session_name} ->
        {cols, rows} = pane_dimensions(pane_id)

        socket =
          socket
          |> maybe_start_heartbeat(review_session_name)
          |> assign(pane_id: pane_id, cols: cols, rows: rows)
          |> recompute_and_push_sync()

        {:noreply, socket}
    end
  end

  def handle_info({:session_registered, _pane_id, session_id}, socket) do
    if session_id == socket.assigns.session_id and is_nil(socket.assigns.pane_id) do
      {pane_id, review_session_name} = find_pane_with_review_info(session_id)
      {cols, rows} = pane_dimensions(pane_id)

      socket =
        socket
        |> maybe_start_heartbeat(review_session_name)
        |> assign(pane_id: pane_id, cols: cols, rows: rows)
        |> recompute_and_push_sync()

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:session_activity, %{session_id: sid, status: status}}, socket) do
    if sid == socket.assigns.session_id do
      {:noreply, assign(socket, session_status: status)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:transcript_updated, session_id, _count}, socket) do
    if session_id == socket.assigns.session_id do
      {:noreply, reload_transcript(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:review_heartbeat, socket) do
    if name = socket.assigns[:review_session_name] do
      ReviewSessionRegistry.heartbeat(name)
      Process.send_after(self(), :review_heartbeat, @review_heartbeat_interval)
    end

    {:noreply, socket}
  end

  def handle_info({:annotation_explain_delta, id, chunk}, socket) do
    streams = socket.assigns.explain_streams
    current = Map.get(streams, id, "")
    {:noreply, assign(socket, explain_streams: Map.put(streams, id, current <> chunk))}
  end

  def handle_info({:annotation_explain_done, id, _final, _refs}, socket) do
    streams = Map.delete(socket.assigns.explain_streams, id)

    {:noreply,
     socket
     |> assign(
       explain_streams: streams,
       annotations: load_annotations(socket.assigns.session_record)
     )}
  end

  def handle_info({:annotation_explain_error, id, _reason}, socket) do
    streams = Map.delete(socket.assigns.explain_streams, id)

    {:noreply,
     socket
     |> assign(
       explain_streams: streams,
       annotations: load_annotations(socket.assigns.session_record)
     )}
  end

  @impl true
  def handle_event("text_selected", params, socket) do
    current_msg_id = socket.assigns.current_message_id

    socket =
      socket
      |> assign(
        selected_text: params["text"],
        selection_source: :terminal,
        selection_message_ids: if(current_msg_id, do: [current_msg_id], else: []),
        selection_start_row: params["start_row"],
        selection_start_col: params["start_col"],
        selection_end_row: params["end_row"],
        selection_end_col: params["end_col"]
      )
      |> maybe_focus_annotations_tab()

    {:noreply, socket}
  end

  def handle_event("transcript_text_selected", params, socket) do
    socket =
      socket
      |> assign(
        selected_text: params["text"],
        selection_source: :transcript,
        selection_message_ids: params["message_ids"] || [],
        selection_start_row: nil,
        selection_start_col: nil,
        selection_end_row: nil,
        selection_end_col: nil
      )
      |> maybe_focus_annotations_tab()

    {:noreply, socket}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply,
     assign(socket,
       selected_text: nil,
       selection_source: nil,
       selection_message_ids: [],
       selection_start_row: nil,
       selection_start_col: nil,
       selection_end_row: nil,
       selection_end_col: nil
     )}
  end

  def handle_event("save_annotation", params, socket) do
    comment = params["comment"] || ""
    purpose = if params["purpose"] == "explain", do: :explain, else: :review
    source = socket.assigns.selection_source || :terminal

    create_params = %{
      session_id: socket.assigns.session_record.id,
      source: source,
      selected_text: socket.assigns.selected_text,
      start_row: socket.assigns.selection_start_row,
      start_col: socket.assigns.selection_start_col,
      end_row: socket.assigns.selection_end_row,
      end_col: socket.assigns.selection_end_col,
      comment: comment,
      purpose: purpose
    }

    case Ash.create(Annotation, create_params) do
      {:ok, annotation} ->
        create_message_refs(annotation, socket)
        if purpose == :review, do: ReviewUpdates.broadcast_counts()

        socket = maybe_enqueue_explain(socket, annotation, purpose)

        {:noreply,
         socket
         |> assign(
           annotations: load_annotations(socket.assigns.session_record),
           selected_text: nil,
           selection_source: nil,
           selection_message_ids: []
         )}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_annotation", %{"id" => id}, socket) do
    case Ash.get(Annotation, id) do
      {:ok, annotation} ->
        Ash.destroy!(annotation)
        ReviewUpdates.broadcast_counts()

        {:noreply, assign(socket, annotations: load_annotations(socket.assigns.session_record))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("highlight_annotation", %{"id" => id}, socket) do
    case Ash.get(Annotation, id, load: [message_refs: :message]) do
      {:ok, %{source: :transcript, message_refs: refs}} when refs != [] ->
        message_ids = refs |> Enum.sort_by(& &1.ordinal) |> Enum.map(& &1.message.id)

        socket =
          socket
          |> push_event("scroll_to_message", %{id: List.first(message_ids)})
          |> push_event("highlight_transcript_annotation", %{message_ids: message_ids})

        {:noreply, socket}

      {:ok, ann} when not is_nil(ann.start_row) ->
        {:noreply,
         push_event(socket, "highlight_annotation", %{
           start_row: ann.start_row,
           start_col: ann.start_col,
           end_row: ann.end_row,
           end_col: ann.end_col
         })}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("jump_to_error", %{"tool-use-id" => tool_use_id}, socket) do
    {:noreply, jump_to_tool_use(socket, tool_use_id)}
  end

  def handle_event("jump_to_rework", %{"tool-use-id" => tool_use_id}, socket) do
    {:noreply, jump_to_tool_use(socket, tool_use_id)}
  end

  def handle_event("toggle_debug", _params, socket) do
    new_debug = !socket.assigns.transcript_view_show_debug

    {:noreply, update_computer_inputs(socket, :transcript_view, %{show_debug: new_debug})}
  end

  def handle_event("switch_sidebar_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_sidebar_tab: String.to_existing_atom(tab))}
  end

  defp maybe_focus_annotations_tab(socket) do
    if socket.assigns.active_sidebar_tab != :annotations do
      socket
      |> assign(active_sidebar_tab: :annotations)
      |> push_event("annotations_attention", %{})
    else
      socket
    end
  end

  defp jump_to_tool_use(socket, tool_use_id) do
    line_index =
      Enum.find_index(socket.assigns.transcript_view_rendered_lines, fn line ->
        line[:tool_use_id] == tool_use_id
      end)

    if line_index do
      push_event(socket, "scroll_to_transcript_line", %{index: line_index})
    else
      socket
    end
  end

  defp compute_sync_data(nil, _rendered_lines), do: {[], []}

  defp compute_sync_data(pane_id, rendered_lines) do
    case Tmux.capture_pane(pane_id) do
      {:ok, capture} ->
        terminal_lines = TranscriptSync.prepare_terminal_lines(capture)
        anchors = TranscriptSync.find_anchors(rendered_lines, terminal_lines)
        breakpoint_map = TranscriptSync.interpolate(anchors, length(terminal_lines))
        {breakpoint_map, anchors}

      {:error, _} ->
        {[], []}
    end
  end

  defp push_sync_events(socket) do
    if connected?(socket) and socket.assigns.breakpoint_map != [] do
      socket
      |> push_event("breakpoint_map", %{entries: socket.assigns.breakpoint_map})
      |> push_event("debug_anchors", %{anchors: socket.assigns.anchors})
    else
      socket
    end
  end

  defp recompute_and_push_sync(socket) do
    {breakpoint_map, anchors} =
      compute_sync_data(socket.assigns.pane_id, socket.assigns.transcript_view_rendered_lines)

    socket
    |> assign(breakpoint_map: breakpoint_map, anchors: anchors)
    |> push_sync_events()
  end

  defp create_message_refs(annotation, socket) do
    message_ids =
      socket.assigns.selection_message_ids
      |> Enum.uniq()
      |> validate_session_message_ids(socket.assigns.session_record)

    message_ids
    |> Enum.with_index()
    |> Enum.each(fn {msg_id, ordinal} ->
      Ash.create!(AnnotationMessageRef, %{
        annotation_id: annotation.id,
        message_id: msg_id,
        ordinal: ordinal
      })
    end)
  end

  defp validate_session_message_ids([], _session), do: []

  defp validate_session_message_ids(ids, session) do
    valid_ids =
      Message
      |> Ash.Query.filter(session_id == ^session.id and id in ^ids)
      |> Ash.Query.select([:id])
      |> Ash.read!()
      |> MapSet.new(& &1.id)

    Enum.filter(ids, &MapSet.member?(valid_ids, &1))
  end

  defp find_pane_with_review_info(session_id) do
    case SessionRegistry.get_pane_id(session_id) do
      nil -> find_review_pane(session_id)
      pane_id -> {pane_id, nil}
    end
  end

  defp find_review_pane(session_id) do
    review_name = "spotter-review-#{String.slice(session_id, 0, 8)}"

    with {:ok, panes} <- Tmux.list_panes(),
         %{pane_id: pane_id} <- Enum.find(panes, &(&1.session_name == review_name)) do
      {pane_id, review_name}
    else
      _ -> {nil, nil}
    end
  end

  defp maybe_start_heartbeat(socket, nil), do: socket

  defp maybe_start_heartbeat(socket, review_session_name) do
    if is_nil(socket.assigns[:review_session_name]) do
      ReviewSessionRegistry.register(review_session_name)
      Process.send_after(self(), :review_heartbeat, @review_heartbeat_interval)
      assign(socket, review_session_name: review_session_name)
    else
      socket
    end
  end

  defp pane_dimensions(nil), do: {80, 24}

  defp pane_dimensions(pane_id) do
    case Tmux.list_panes() do
      {:ok, panes} ->
        case Enum.find(panes, &(&1.pane_id == pane_id)) do
          %{pane_width: w, pane_height: h} -> {w, h}
          _ -> {80, 24}
        end

      _ ->
        {80, 24}
    end
  end

  defp reload_transcript(socket) do
    session_id = socket.assigns.session_id
    {session_record, messages} = load_session_data(session_id)

    session_cwd = if session_record, do: session_record.cwd, else: nil
    {link_project_id, link_fileset} = resolve_file_link_context(session_record)

    errors = load_errors(session_record)
    rework_events = load_rework_events(session_record)
    commit_links = load_commit_links(session_id)

    socket =
      socket
      |> assign(
        session_record: session_record,
        errors: errors,
        rework_events: rework_events,
        commit_links: commit_links,
        subagent_labels: load_subagent_labels(session_record),
        transcript_link_project_id: link_project_id,
        transcript_link_fileset: link_fileset
      )
      |> update_computer_inputs(:transcript_view, %{
        messages: messages,
        session_cwd: session_cwd
      })

    rendered_lines = socket.assigns.transcript_view_rendered_lines
    {breakpoint_map, anchors} = compute_sync_data(socket.assigns.pane_id, rendered_lines)

    socket
    |> assign(breakpoint_map: breakpoint_map, anchors: anchors)
    |> push_sync_events()
  end

  defp resolve_file_link_context(nil), do: {nil, nil}

  defp resolve_file_link_context(session_record) do
    project_id = to_string(session_record.project_id)

    case TranscriptFileLinks.for_session(session_record.cwd) do
      {:ok, %{files: files}} -> {project_id, files}
      {:error, _} -> {project_id, nil}
    end
  rescue
    exception ->
      Logger.warning(
        "SessionLive.resolve_file_link_context/1 rescued #{inspect(exception.__struct__)}"
      )

      {to_string(session_record.project_id), nil}
  end

  defp load_session_data(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %Session{} = session} ->
        session = maybe_bootstrap_sync(session)
        messages = load_session_messages(session)
        {session, messages}

      _ ->
        {nil, []}
    end
  rescue
    _ -> {nil, []}
  end

  defp maybe_bootstrap_sync(%Session{message_count: count} = session)
       when is_nil(count) or count == 0 do
    case SyncTranscripts.sync_session_by_id(session.session_id) do
      %{status: :ok} ->
        # Reload session to get updated attributes
        case Session |> Ash.Query.filter(session_id == ^session.session_id) |> Ash.read_one() do
          {:ok, %Session{} = refreshed} -> refreshed
          _ -> session
        end

      _ ->
        session
    end
  end

  defp maybe_bootstrap_sync(session), do: session

  defp load_subagent_labels(nil), do: %{}

  defp load_subagent_labels(session) do
    Subagent
    |> Ash.Query.filter(session_id == ^session.id)
    |> Ash.Query.select([:agent_id, :slug])
    |> Ash.read!()
    |> Map.new(fn sa ->
      {sa.agent_id, sa.slug || String.slice(sa.agent_id, 0, 7)}
    end)
  end

  defp load_errors(nil), do: []

  defp load_errors(session) do
    ToolCall
    |> Ash.Query.filter(session_id == ^session.id and is_error == true)
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!()
  end

  defp load_rework_events(nil), do: []

  defp load_rework_events(session) do
    SessionRework
    |> Ash.Query.filter(session_id == ^session.id)
    |> Ash.Query.sort(occurrence_index: :asc, event_timestamp: :asc)
    |> Ash.read!()
  end

  defp maybe_enqueue_explain(socket, annotation, :explain) do
    # Subscribe BEFORE enqueue to prevent race: if the job completes before
    # subscription, the done broadcast would be missed, leaving UI stuck streaming.
    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Spotter.PubSub,
        ExplainAnnotations.topic(annotation.id)
      )
    end

    streams = Map.put(socket.assigns.explain_streams, annotation.id, "")
    socket = assign(socket, explain_streams: streams)

    case explain_annotations_module().enqueue(annotation.id) do
      {:ok, _job} ->
        socket

      {:error, _reason} ->
        socket
        |> assign(explain_streams: Map.delete(socket.assigns.explain_streams, annotation.id))
        |> put_flash(:error, "Could not start explanation job.")
    end
  end

  defp maybe_enqueue_explain(socket, _annotation, _purpose), do: socket

  defp explain_annotations_module do
    Application.get_env(:spotter, :explain_annotations_module, ExplainAnnotations)
  end

  defp load_annotations(nil), do: []

  defp load_annotations(%Session{id: id}) do
    Annotation
    |> Ash.Query.filter(session_id == ^id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
    |> Ash.load!(message_refs: :message)
  end

  defp load_session_messages(session) do
    Message
    |> Ash.Query.filter(session_id == ^session.id and is_nil(subagent_id))
    |> Ash.Query.sort(timestamp: :asc)
    |> Ash.read!()
    |> Enum.map(fn msg ->
      %{
        id: msg.id,
        uuid: msg.uuid,
        type: msg.type,
        role: msg.role,
        content: msg.content,
        raw_payload: msg.raw_payload,
        timestamp: msg.timestamp,
        agent_id: msg.agent_id
      }
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div data-testid="session-root">
      <div class="breadcrumb">
        <a href="/">Dashboard</a>
        <span class="breadcrumb-sep">/</span>
        <span class="breadcrumb-current">Session {String.slice(@session_id, 0..7)}</span>
        <span :if={@pane_id} class="breadcrumb-meta">
          Pane: {@pane_id}
        </span>
        <span :if={@session_status} class={"badge session-status-#{@session_status}"}>
          {@session_status}
        </span>
      </div>
      <.distilled_summary_section session_record={@session_record} />
      <div class="session-layout">
        <div class="session-terminal">
          <div class="session-terminal-inner">
            <%= if @pane_id do %>
              <div
                id="terminal"
                phx-hook="Terminal"
                data-pane-id={@pane_id}
                data-cols={@cols}
                data-rows={@rows}
                phx-update="ignore"
                class="terminal-container"
              >
              </div>
            <% else %>
              <div class="terminal-connecting">
                <div>
                  <div class="terminal-connecting-title">Connecting to session...</div>
                  <div class="terminal-connecting-subtitle">Waiting for terminal to be ready</div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <div id="transcript-panel" class="session-transcript" data-testid="transcript-container">
          <div class="transcript-header">
            <h3>Transcript</h3>
            <span class={"transcript-header-hint#{if @transcript_view_show_debug, do: " debug-active", else: ""}"}>
              <%= if @transcript_view_show_debug, do: "DEBUG ON", else: "Ctrl+Shift+D: debug" %>
            </span>
          </div>

          <.transcript_panel
            rendered_lines={@transcript_view_visible_lines}
            all_rendered_lines={@transcript_view_rendered_lines}
            expanded_tool_groups={@transcript_view_expanded_tool_groups}
            expanded_hook_groups={@transcript_view_expanded_hook_groups}
            current_message_id={@current_message_id}
            clicked_subagent={@clicked_subagent}
            session_id={@session_id}
            subagent_labels={@subagent_labels}
            show_debug={@transcript_view_show_debug}
            anchors={@anchors}
            project_id={@transcript_link_project_id}
            existing_files={@transcript_link_fileset}
            empty_message="No transcript available for this session."
          />
        </div>
        <div class="session-sidebar">
        <div class="sidebar-tabs">
          <button
            class={"sidebar-tab#{if @active_sidebar_tab == :commits, do: " is-active"}"}
            phx-click="switch_sidebar_tab"
            phx-value-tab="commits"
          >
            Commits ({length(@commit_links)})
          </button>
          <button
            id="sidebar-tab-annotations"
            class={"sidebar-tab#{if @active_sidebar_tab == :annotations, do: " is-active"}"}
            phx-click="switch_sidebar_tab"
            phx-value-tab="annotations"
          >
            Annotations ({length(@annotations)})
          </button>
          <button
            class={"sidebar-tab#{if @active_sidebar_tab == :errors, do: " is-active"}"}
            phx-click="switch_sidebar_tab"
            phx-value-tab="errors"
          >
            Errors ({length(@errors)})
          </button>
          <button
            class={"sidebar-tab#{if @active_sidebar_tab == :rework, do: " is-active"}"}
            phx-click="switch_sidebar_tab"
            phx-value-tab="rework"
          >
            Rework ({length(@rework_events)})
          </button>
        </div>

        <%!-- Commits tab --%>
        <div :if={@active_sidebar_tab == :commits} class="sidebar-tab-content">
          <%= if @commit_links == [] do %>
            <p class="text-muted text-sm">No linked commits yet.</p>
          <% else %>
            <%= for %{link: link, commit: commit} <- @commit_links do %>
              <div class="commit-card">
                <div class="flex items-center gap-2">
                  <code class="commit-hash">
                    <%= String.slice(commit.commit_hash, 0, 8) %>
                  </code>
                  <%= if link.link_type == :observed_in_session do %>
                    <span class="badge badge-verified">Verified</span>
                  <% else %>
                    <span class="badge badge-inferred">Inferred <%= round(link.confidence * 100) %>%</span>
                  <% end %>
                </div>
                <div class="commit-subject">
                  <%= commit.subject || "(no subject)" %>
                </div>
                <div :if={commit.git_branch} class="commit-branch">
                  <%= commit.git_branch %>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <%!-- Annotations tab --%>
        <div :if={@active_sidebar_tab == :annotations} class="sidebar-tab-content">
          <.annotation_editor
            :if={@selected_text}
            selected_text={@selected_text}
            selection_label={selection_label(@selection_source, @selection_message_ids)}
          />

          <.annotation_cards
            annotations={@annotations}
            explain_streams={@explain_streams}
            empty_message="Select text in terminal or transcript to add annotations."
          />
        </div>

        <%!-- Errors tab --%>
        <div :if={@active_sidebar_tab == :errors} class="sidebar-tab-content">
          <%= if @errors == [] do %>
            <p class="text-muted text-sm">No errors detected.</p>
          <% else %>
            <div
              :for={error <- @errors}
              phx-click="jump_to_error"
              phx-value-tool-use-id={error.tool_use_id}
              class="transcript-error-item"
            >
              <span class="error-tool">{error.tool_name}</span>
              <span :if={error.error_content} class="error-content">
                {String.slice(error.error_content, 0, 100)}
              </span>
            </div>
          <% end %>
        </div>

        <%!-- Rework tab --%>
        <div :if={@active_sidebar_tab == :rework} class="sidebar-tab-content">
          <%= if @rework_events == [] do %>
            <p class="text-muted text-sm">No rework detected.</p>
          <% else %>
            <div
              :for={event <- @rework_events}
              phx-click="jump_to_rework"
              phx-value-tool-use-id={event.tool_use_id}
              class="transcript-rework-item"
            >
              <span class="rework-file">{event.relative_path || event.file_path}</span>
              <span class="rework-occurrence">#{event.occurrence_index}</span>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    </div>
    """
  end

  defp distilled_summary_section(%{session_record: nil} = assigns) do
    ~H""
  end

  defp distilled_summary_section(%{session_record: record} = assigns) do
    assigns = assign(assigns, :status, record.distilled_status)

    ~H"""
    <div class="session-summary-section" data-testid="distilled-summary">
      <%= case @status do %>
        <% :completed -> %>
          <pre class="session-summary">{@session_record.distilled_summary}</pre>
        <% :pending -> %>
          <div class="text-muted text-sm">Summary pending...</div>
        <% :skipped -> %>
          <div class="text-muted text-sm">No summary (no commit links)</div>
        <% :error -> %>
          <div class="text-error text-sm">Summary failed</div>
        <% _ -> %>
      <% end %>
    </div>
    """
  end

  defp load_commit_links(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %Session{id: id}} ->
        links =
          SessionCommitLink
          |> Ash.Query.filter(session_id == ^id)
          |> Ash.Query.sort(inserted_at: :desc)
          |> Ash.read!()

        commit_ids =
          links
          |> Enum.map(& &1.commit_id)
          |> Enum.reject(&is_nil/1)

        commits_by_id =
          if commit_ids == [] do
            %{}
          else
            Commit
            |> Ash.Query.filter(id in ^commit_ids)
            |> Ash.read!()
            |> Map.new(&{&1.id, &1})
          end

        Enum.map(links, fn link ->
          commit = Map.get(commits_by_id, link.commit_id)
          %{link: link, commit: commit}
        end)
        |> Enum.reject(&is_nil(&1.commit))
        |> Enum.sort_by(
          fn %{commit: c} -> c.committed_at || c.inserted_at end,
          {:desc, DateTime}
        )

      _ ->
        []
    end
  end
end
