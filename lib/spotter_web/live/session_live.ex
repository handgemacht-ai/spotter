defmodule SpotterWeb.SessionLive do
  use Phoenix.LiveView

  alias Spotter.Services.{
    ReviewSessionRegistry,
    SessionRegistry,
    Tmux,
    TranscriptRenderer,
    TranscriptSync
  }

  alias Spotter.Transcripts.{
    Annotation,
    AnnotationMessageRef,
    Commit,
    Message,
    Session,
    SessionCommitLink,
    SessionRework,
    ToolCall
  }

  require Ash.Query

  @review_heartbeat_interval 10_000

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    {pane_id, review_session_name} = find_pane_with_review_info(session_id)

    {cols, rows} = pane_dimensions(pane_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Spotter.PubSub, "pane_sessions")

      if is_nil(pane_id) do
        Process.send_after(self(), :check_pane, 1_000)
      end

      if review_session_name do
        ReviewSessionRegistry.register(review_session_name)
        Process.send_after(self(), :review_heartbeat, @review_heartbeat_interval)
      end
    end

    {session_record, messages, rendered_lines} = load_transcript(session_id)
    annotations = load_annotations(session_record)
    errors = load_errors(session_record)
    rework_events = load_rework_events(session_record)
    commit_links = load_commit_links(session_id)
    {breakpoint_map, anchors} = compute_sync_data(pane_id, rendered_lines)

    socket =
      assign(socket,
        pane_id: pane_id,
        session_id: session_id,
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
        messages: messages,
        rendered_lines: rendered_lines,
        errors: errors,
        rework_events: rework_events,
        commit_links: commit_links,
        current_message_id: nil,
        show_transcript: true,
        breakpoint_map: breakpoint_map,
        anchors: anchors,
        show_debug: false,
        clicked_subagent: nil,
        active_sidebar_tab: :commits
      )

    socket = push_sync_events(socket)

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

  def handle_info(:review_heartbeat, socket) do
    if name = socket.assigns[:review_session_name] do
      ReviewSessionRegistry.heartbeat(name)
      Process.send_after(self(), :review_heartbeat, @review_heartbeat_interval)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("text_selected", params, socket) do
    current_msg_id = socket.assigns.current_message_id

    {:noreply,
     assign(socket,
       selected_text: params["text"],
       selection_source: :terminal,
       selection_message_ids: if(current_msg_id, do: [current_msg_id], else: []),
       selection_start_row: params["start_row"],
       selection_start_col: params["start_col"],
       selection_end_row: params["end_row"],
       selection_end_col: params["end_col"]
     )}
  end

  def handle_event("transcript_text_selected", params, socket) do
    {:noreply,
     assign(socket,
       selected_text: params["text"],
       selection_source: :transcript,
       selection_message_ids: params["message_ids"] || [],
       selection_start_row: nil,
       selection_start_col: nil,
       selection_end_row: nil,
       selection_end_col: nil
     )}
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

  def handle_event("save_annotation", %{"comment" => comment}, socket) do
    source = socket.assigns.selection_source || :terminal

    params = %{
      session_id: socket.assigns.session_record.id,
      source: source,
      selected_text: socket.assigns.selected_text,
      start_row: socket.assigns.selection_start_row,
      start_col: socket.assigns.selection_start_col,
      end_row: socket.assigns.selection_end_row,
      end_col: socket.assigns.selection_end_col,
      comment: comment
    }

    case Ash.create(Annotation, params) do
      {:ok, annotation} ->
        create_message_refs(annotation, socket)

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
    {:noreply, assign(socket, show_debug: !socket.assigns.show_debug)}
  end

  def handle_event("subagent_reference_clicked", %{"ref" => ref}, socket) do
    {:noreply, assign(socket, clicked_subagent: ref)}
  end

  def handle_event("switch_sidebar_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_sidebar_tab: String.to_existing_atom(tab))}
  end

  defp jump_to_tool_use(socket, tool_use_id) do
    line_index =
      Enum.find_index(socket.assigns.rendered_lines, fn line ->
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
      compute_sync_data(socket.assigns.pane_id, socket.assigns.rendered_lines)

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

  defp load_transcript(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %Session{} = session} ->
        messages = load_session_messages(session)
        opts = if session.cwd, do: [session_cwd: session.cwd], else: []
        {session, messages, TranscriptRenderer.render(messages, opts)}

      _ ->
        {nil, [], []}
    end
  rescue
    _ -> {nil, [], []}
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
        timestamp: msg.timestamp,
        agent_id: msg.agent_id
      }
    end)
  end

  defp selection_label(:transcript, [_ | _] = message_ids) do
    "Selected transcript text (#{length(message_ids)} messages)"
  end

  defp selection_label(:transcript, _), do: "Selected transcript text"
  defp selection_label(_, _), do: "Selected terminal text"

  defp source_badge(:transcript), do: "Transcript"
  defp source_badge(_), do: "Terminal"

  defp source_badge_color(:transcript),
    do: "background: rgba(91, 156, 245, 0.15); color: var(--accent-blue);"

  defp source_badge_color(_),
    do: "background: rgba(229, 168, 75, 0.15); color: var(--accent-amber);"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="breadcrumb">
      <a href="/">Dashboard</a>
      <span class="breadcrumb-sep">/</span>
      <span class="breadcrumb-current">Session {String.slice(@session_id, 0..7)}</span>
      <span :if={@pane_id} class="breadcrumb-meta">
        Pane: {@pane_id}
      </span>
    </div>
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
      <div id="transcript-panel" class="session-transcript">
        <div class="transcript-header">
          <h3>Transcript</h3>
          <span class={"transcript-header-hint#{if @show_debug, do: " debug-active", else: ""}"}>
            {if @show_debug, do: "DEBUG ON", else: "Ctrl+Shift+D: debug"}
          </span>
        </div>

        <%= if @errors != [] do %>
          <div class="transcript-error-panel">
            <div class="error-title">Errors ({length(@errors)})</div>
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
          </div>
        <% end %>

        <%= if @rework_events != [] do %>
          <div class="transcript-rework-panel">
            <div class="rework-title">Rework ({length(@rework_events)})</div>
            <div
              :for={event <- @rework_events}
              phx-click="jump_to_rework"
              phx-value-tool-use-id={event.tool_use_id}
              class="transcript-rework-item"
            >
              <span class="rework-file">{event.relative_path || event.file_path}</span>
              <span class="rework-occurrence">#{event.occurrence_index}</span>
            </div>
          </div>
        <% end %>

        <%= if @rendered_lines != [] do %>
          <div id="transcript-messages" phx-hook="TranscriptHighlighter" phx-update="replace">
            <%= for line <- @rendered_lines do %>
              <div
                id={"msg-#{line.line_number}"}
                data-message-id={line.message_id}
                class={transcript_row_classes(line, @current_message_id, @clicked_subagent)}
                data-render-mode={to_string(line[:render_mode] || "plain")}
              >
                <%= if @show_debug do %>
                  <% anchor = Enum.find(@anchors, & &1.tl == line.line_number) %>
                  <span
                    :if={anchor}
                    style={"display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:4px;background:#{anchor_color(anchor.type)};"}
                    title={"#{anchor.type} → terminal line #{anchor.t}"}
                  />
                <% end %>
                <%= if line[:subagent_ref] do %>
                  <span
                    class="subagent-badge"
                    phx-click="subagent_reference_clicked"
                    phx-value-ref={line.subagent_ref}
                  >
                    agent
                  </span>
                <% end %>
                <%= if line[:render_mode] == :code do %>
                  <pre class="row-text row-text-code"><code class={"language-#{line[:code_language] || "plaintext"}"}><%= line.line %></code></pre>
                <% else %>
                  <span class="row-text"><%= line.line %></span>
                <% end %>
              </div>
            <% end %>
          </div>
        <% else %>
          <p class="transcript-empty">No transcript available for this session.</p>
        <% end %>
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
          <%= if @selected_text do %>
            <div class="annotation-form">
              <div class="annotation-form-hint">
                {selection_label(@selection_source, @selection_message_ids)}
              </div>
              <pre class="annotation-form-preview"><%= @selected_text %></pre>
              <form phx-submit="save_annotation">
                <textarea
                  name="comment"
                  placeholder="Add a comment..."
                  required
                  class="annotation-form-textarea"
                />
                <div class="annotation-form-actions">
                  <button type="submit" class="btn btn-success">Save</button>
                  <button type="button" class="btn" phx-click="clear_selection">Cancel</button>
                </div>
              </form>
            </div>
          <% end %>

          <%= if @annotations == [] do %>
            <p class="text-muted text-sm">Select text in terminal or transcript to add annotations.</p>
          <% end %>

          <%= for ann <- @annotations do %>
            <div class="annotation-card" phx-click="highlight_annotation" phx-value-id={ann.id}>
              <div class="flex items-center gap-2 mb-2">
                <span style={"font-size: var(--text-xs); padding: 1px 6px; border-radius: 3px; #{source_badge_color(ann.source)}"}>
                  {source_badge(ann.source)}
                </span>
                <span :if={ann.source == :transcript && ann.message_refs != []} class="text-muted text-xs">
                  {length(ann.message_refs)} messages
                </span>
              </div>
              <pre class="annotation-text"><%= ann.selected_text %></pre>
              <p class="annotation-comment"><%= ann.comment %></p>
              <div class="annotation-meta">
                <span class="annotation-time"><%= Calendar.strftime(ann.inserted_at, "%H:%M") %></span>
                <button class="btn-ghost text-error text-xs" phx-click="delete_annotation" phx-value-id={ann.id}>
                  Delete
                </button>
              </div>
            </div>
          <% end %>
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
      </div>
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

        commit_ids = Enum.map(links, & &1.commit_id)

        commits_by_id =
          Commit
          |> Ash.Query.filter(id in ^commit_ids)
          |> Ash.read!()
          |> Map.new(&{&1.id, &1})

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

  defp transcript_row_classes(line, current_message_id, clicked_subagent) do
    kind =
      case line[:kind] do
        :tool_use -> ["is-tool-use"]
        :tool_result -> ["is-tool-result"]
        :thinking -> ["is-thinking"]
        _ -> []
      end

    type = if line.type == :user, do: ["is-user"], else: []
    code = if line[:render_mode] == :code, do: ["is-code"], else: []
    active = if current_message_id == line.message_id, do: ["is-active"], else: []

    classes = ["transcript-row"] ++ kind ++ type ++ code ++ active
    classes = classes ++ subagent_classes(line[:subagent_ref], clicked_subagent)
    Enum.join(classes, " ")
  end

  defp subagent_classes(nil, _clicked), do: []

  defp subagent_classes(ref, clicked) do
    if clicked == ref, do: ["is-subagent", "is-clicked"], else: ["is-subagent"]
  end

  defp anchor_color(:tool_use), do: "var(--accent-amber)"
  defp anchor_color(:user), do: "var(--accent-blue)"
  defp anchor_color(:result), do: "var(--accent-green)"
  defp anchor_color(:text), do: "var(--accent-purple)"
  defp anchor_color(_), do: "var(--text-tertiary)"
end
