defmodule SpotterWeb.SessionLive do
  use Phoenix.LiveView

  alias Spotter.Services.{ReviewSessionRegistry, SessionRegistry, Tmux, TranscriptRenderer}
  alias Spotter.Transcripts.{Annotation, Commit, Message, Session, SessionCommitLink, ToolCall}
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
    commit_links = load_commit_links(session_id)

    {:ok,
     assign(socket,
       pane_id: pane_id,
       session_id: session_id,
       session_record: session_record,
       review_session_name: review_session_name,
       cols: cols,
       rows: rows,
       annotations: annotations,
       selected_text: nil,
       selection_start_row: nil,
       selection_start_col: nil,
       selection_end_row: nil,
       selection_end_col: nil,
       messages: messages,
       rendered_lines: rendered_lines,
       errors: errors,
       commit_links: commit_links,
       current_message_id: nil,
       show_transcript: true
     )}
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
        socket = maybe_start_heartbeat(socket, review_session_name)
        {:noreply, assign(socket, pane_id: pane_id, cols: cols, rows: rows)}
    end
  end

  def handle_info({:session_registered, _pane_id, session_id}, socket) do
    if session_id == socket.assigns.session_id and is_nil(socket.assigns.pane_id) do
      {pane_id, review_session_name} = find_pane_with_review_info(session_id)
      {cols, rows} = pane_dimensions(pane_id)
      socket = maybe_start_heartbeat(socket, review_session_name)
      {:noreply, assign(socket, pane_id: pane_id, cols: cols, rows: rows)}
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
    {:noreply,
     assign(socket,
       selected_text: params["text"],
       selection_start_row: params["start_row"],
       selection_start_col: params["start_col"],
       selection_end_row: params["end_row"],
       selection_end_col: params["end_col"]
     )}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply,
     assign(socket,
       selected_text: nil,
       selection_start_row: nil,
       selection_start_col: nil,
       selection_end_row: nil,
       selection_end_col: nil
     )}
  end

  def handle_event("save_annotation", %{"comment" => comment}, socket) do
    params = %{
      session_id: socket.assigns.session_record.id,
      selected_text: socket.assigns.selected_text,
      start_row: socket.assigns.selection_start_row,
      start_col: socket.assigns.selection_start_col,
      end_row: socket.assigns.selection_end_row,
      end_col: socket.assigns.selection_end_col,
      comment: comment
    }

    case Ash.create(Annotation, params) do
      {:ok, _annotation} ->
        {:noreply,
         socket
         |> assign(
           annotations: load_annotations(socket.assigns.session_record),
           selected_text: nil
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
    case Ash.get(Annotation, id) do
      {:ok, ann} ->
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
    line_index =
      Enum.find_index(socket.assigns.rendered_lines, fn line ->
        line[:tool_use_id] == tool_use_id
      end)

    socket =
      if line_index do
        push_event(socket, "scroll_to_transcript_line", %{index: line_index})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("terminal_scrolled", %{"visible_text" => visible_text}, socket) do
    current_message_id = find_matching_message(visible_text, socket.assigns.rendered_lines)

    socket =
      if current_message_id && current_message_id != socket.assigns.current_message_id do
        socket
        |> assign(current_message_id: current_message_id)
        |> push_event("scroll_to_message", %{id: current_message_id})
      else
        socket
      end

    {:noreply, socket}
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
        {session, messages, TranscriptRenderer.render(messages)}

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

  defp load_annotations(nil), do: []

  defp load_annotations(%Session{id: id}) do
    Annotation
    |> Ash.Query.filter(session_id == ^id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
  end

  defp load_session_messages(session) do
    Message
    |> Ash.Query.filter(session_id == ^session.id)
    |> Ash.Query.sort(timestamp: :asc)
    |> Ash.read!()
    |> Enum.map(fn msg ->
      %{
        uuid: msg.uuid,
        type: msg.type,
        role: msg.role,
        content: msg.content,
        timestamp: msg.timestamp
      }
    end)
  end

  defp find_matching_message(visible_text, rendered_lines) do
    visible_text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.find_value(&match_line_to_message(&1, rendered_lines))
  end

  defp match_line_to_message(trimmed_line, rendered_lines) do
    Enum.find_value(rendered_lines, fn %{line: line, message_id: msg_id} ->
      if String.contains?(line, trimmed_line), do: msg_id
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="header">
      <a href="/">&larr; Back</a>
      <span>Session: {String.slice(@session_id, 0..7)}</span>
      <span :if={@pane_id} style="color: #888; margin-left: 1rem; font-size: 0.85em;">
        Pane: {@pane_id}
      </span>
    </div>
    <div style="display: flex; gap: 0; height: calc(100vh - 50px);">
      <div style="flex: 2; overflow-x: auto; padding: 1rem;">
        <div style="display: inline-block; min-width: 100%;">
          <%= if @pane_id do %>
            <div
              id="terminal"
              phx-hook="Terminal"
              data-pane-id={@pane_id}
              data-cols={@cols}
              data-rows={@rows}
              phx-update="ignore"
              style="display: inline-block;"
            >
            </div>
          <% else %>
            <div style="display: flex; align-items: center; justify-content: center; height: 100%; color: #888;">
              <div style="text-align: center;">
                <div style="font-size: 1.2em; margin-bottom: 0.5rem;">Connecting to session...</div>
                <div style="color: #555; font-size: 0.9em;">Waiting for terminal to be ready</div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
      <div style="flex: 1; background: #0d1117; padding: 1rem; overflow-y: auto; border-left: 1px solid #2a2a4a;"
           id="transcript-panel">
        <h3 style="margin: 0 0 0.75rem 0; color: #64b5f6;">Transcript</h3>

        <%= if @errors != [] do %>
          <div style="margin-bottom: 1rem; background: #1a1a2e; border-radius: 6px; padding: 0.75rem;">
            <div style="color: #f87171; font-size: 0.85em; font-weight: bold; margin-bottom: 0.5rem;">
              Errors ({length(@errors)})
            </div>
            <div :for={error <- @errors}
              phx-click="jump_to_error"
              phx-value-tool-use-id={error.tool_use_id}
              style="padding: 4px 6px; margin-bottom: 4px; cursor: pointer; border-radius: 4px; font-size: 0.8em;"
              class="hover:bg-gray-800"
            >
              <span style="color: #f87171; font-weight: bold;">{error.tool_name}</span>
              <span :if={error.error_content} style="color: #888; margin-left: 0.5rem;">
                {String.slice(error.error_content, 0, 100)}
              </span>
            </div>
          </div>
        <% end %>

        <%= if @rendered_lines != [] do %>
          <div id="transcript-messages" style="font-family: 'JetBrains Mono', monospace; font-size: 0.8em;">
            <%= for line <- @rendered_lines do %>
              <div
                id={"msg-#{line.line_number}"}
                data-message-id={line.message_id}
                style={"padding: 2px 6px; #{if @current_message_id == line.message_id, do: "background: #1a2744; border-left: 2px solid #64b5f6;", else: "border-left: 2px solid transparent;"}"}
              >
                <span style={type_color(line.type)}><%= line.line %></span>
              </div>
            <% end %>
          </div>
        <% else %>
          <p style="color: #666; font-style: italic; font-size: 0.85em;">
            No transcript available for this session.
          </p>
        <% end %>
      </div>
      <div style="flex: 1; background: #16213e; padding: 1rem; overflow-y: auto; border-left: 1px solid #2a2a4a;">
        <h3 style="margin: 0 0 0.75rem 0; color: #64b5f6;">Commits</h3>

        <%= if @commit_links == [] do %>
          <p style="color: #666; font-style: italic; font-size: 0.85em; margin-bottom: 1rem;">
            No linked commits yet.
          </p>
        <% else %>
          <div style="margin-bottom: 1rem;">
            <%= for %{link: link, commit: commit} <- @commit_links do %>
              <div style="background: #1a1a2e; border-radius: 6px; padding: 0.6rem; margin-bottom: 0.4rem;">
                <div style="display: flex; align-items: center; gap: 0.5rem;">
                  <code style="color: #f0c674; font-size: 0.85em;">
                    <%= String.slice(commit.commit_hash, 0, 8) %>
                  </code>
                  <%= if link.link_type == :observed_in_session do %>
                    <span style="background: #1a6b3c; color: #e0e0e0; font-size: 0.7em; padding: 1px 6px; border-radius: 3px;">
                      Verified
                    </span>
                  <% else %>
                    <span style="background: #6b4c1a; color: #e0e0e0; font-size: 0.7em; padding: 1px 6px; border-radius: 3px;">
                      Inferred <%= round(link.confidence * 100) %>%
                    </span>
                  <% end %>
                </div>
                <div style="color: #c0c0c0; font-size: 0.8em; margin-top: 0.25rem;">
                  <%= commit.subject || "(no subject)" %>
                </div>
                <div :if={commit.git_branch} style="color: #666; font-size: 0.7em; margin-top: 0.15rem;">
                  <%= commit.git_branch %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>

        <h3 style="margin: 0 0 1rem 0; color: #64b5f6;">Annotations</h3>

        <%= if @selected_text do %>
          <div style="background: #1a1a2e; border-radius: 6px; padding: 0.75rem; margin-bottom: 1rem;">
            <div style="font-size: 0.8em; color: #888; margin-bottom: 0.5rem;">Selected text:</div>
            <pre style="margin: 0 0 0.75rem 0; color: #e0e0e0; white-space: pre-wrap; font-size: 0.85em; max-height: 100px; overflow-y: auto;"><%= @selected_text %></pre>
            <form phx-submit="save_annotation">
              <textarea
                name="comment"
                placeholder="Add a comment..."
                required
                style="width: 100%; min-height: 60px; background: #0d1117; color: #e0e0e0; border: 1px solid #2a2a4a; border-radius: 4px; padding: 0.5rem; font-family: inherit; resize: vertical;"
              />
              <div style="display: flex; gap: 0.5rem; margin-top: 0.5rem;">
                <button type="submit" style="background: #1a6b3c; color: #e0e0e0; border: none; border-radius: 4px; padding: 0.4rem 0.8rem; cursor: pointer;">
                  Save
                </button>
                <button type="button" phx-click="clear_selection" style="background: #333; color: #e0e0e0; border: none; border-radius: 4px; padding: 0.4rem 0.8rem; cursor: pointer;">
                  Cancel
                </button>
              </div>
            </form>
          </div>
        <% end %>

        <%= if @annotations == [] do %>
          <p style="color: #666; font-style: italic;">Select text in the terminal to add annotations.</p>
        <% end %>

        <%= for ann <- @annotations do %>
          <div
            style="background: #1a1a2e; border-radius: 6px; padding: 0.75rem; margin-bottom: 0.5rem; cursor: pointer;"
            phx-click="highlight_annotation"
            phx-value-id={ann.id}
          >
            <pre style="margin: 0 0 0.5rem 0; color: #a0a0a0; white-space: pre-wrap; font-size: 0.8em; max-height: 60px; overflow-y: auto;"><%= ann.selected_text %></pre>
            <p style="margin: 0; color: #e0e0e0; font-size: 0.9em;"><%= ann.comment %></p>
            <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 0.5rem;">
              <span style="font-size: 0.75em; color: #555;"><%= Calendar.strftime(ann.inserted_at, "%H:%M") %></span>
              <button
                phx-click="delete_annotation"
                phx-value-id={ann.id}
                style="background: none; border: none; color: #c0392b; cursor: pointer; font-size: 0.8em;"
              >
                Delete
              </button>
            </div>
          </div>
        <% end %>
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

  defp type_color(:assistant), do: "color: #e0e0e0;"
  defp type_color(:user), do: "color: #7ec8e3;"
  defp type_color(_), do: "color: #888;"
end
