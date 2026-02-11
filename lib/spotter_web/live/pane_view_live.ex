defmodule SpotterWeb.PaneViewLive do
  use Phoenix.LiveView

  alias Spotter.Services.{SessionRegistry, TranscriptRenderer, Tmux}
  alias Spotter.Transcripts.{Annotation, Message, Session}
  require Ash.Query

  @impl true
  def mount(%{"pane_id" => pane_num}, _session, socket) do
    pane_id = Tmux.num_to_pane_id(pane_num)

    {cols, rows} =
      case Tmux.list_panes() do
        {:ok, panes} ->
          case Enum.find(panes, &(&1.pane_id == pane_id)) do
            %{pane_width: w, pane_height: h} -> {w, h}
            _ -> {80, 24}
          end

        _ ->
          {80, 24}
      end

    session_id = SessionRegistry.get_session_id(pane_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Spotter.PubSub, "pane_sessions")
    end

    annotations = load_annotations(session_id)
    available_sessions = load_available_sessions()

    {:ok,
     assign(socket,
       pane_id: pane_id,
       session_id: session_id,
       cols: cols,
       rows: rows,
       annotations: annotations,
       selected_text: nil,
       selection_start_row: nil,
       selection_start_col: nil,
       selection_end_row: nil,
       selection_end_col: nil,
       available_sessions: available_sessions,
       session: nil,
       messages: [],
       rendered_lines: [],
       current_message_id: nil,
       show_transcript: true
     )}
  end

  @impl true
  def handle_info({:session_registered, pane_id, session_id}, socket) do
    if pane_id == socket.assigns.pane_id do
      {:noreply,
       socket
       |> assign(session_id: session_id, annotations: load_annotations(session_id))}
    else
      {:noreply, socket}
    end
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
    session_id = socket.assigns.session_id

    if is_nil(session_id) do
      {:noreply, socket}
    else
      params = %{
        session_id: session_id,
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
             annotations: load_annotations(session_id),
             selected_text: nil
           )}

        {:error, _} ->
          {:noreply, socket}
      end
    end
  end

  def handle_event("delete_annotation", %{"id" => id}, socket) do
    case Ash.get(Annotation, id) do
      {:ok, annotation} ->
        Ash.destroy!(annotation)

        {:noreply, assign(socket, annotations: load_annotations(socket.assigns.session_id))}

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

  def handle_event("select_session", %{"session_id" => session_id}, socket) do
    case Ash.get(Session, session_id) do
      {:ok, session} ->
        messages = load_session_messages(session)
        rendered_lines = TranscriptRenderer.render(messages)

        {:noreply,
         assign(socket,
           session: session,
           messages: messages,
           rendered_lines: rendered_lines,
           current_message_id: nil
         )}

      _ ->
        {:noreply, socket}
    end
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

  defp load_annotations(nil), do: []

  defp load_annotations(session_id) do
    Annotation
    |> Ash.Query.filter(session_id == ^session_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
  end

  defp load_available_sessions do
    Session
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.Query.limit(20)
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
      <span>Pane: {@pane_id}</span>
      <span :if={@session_id} style="color: #64b5f6; margin-left: 1rem; font-size: 0.85em;">
        Session: {String.slice(@session_id, 0..7)}
      </span>
    </div>
    <div style="display: flex; gap: 0; height: calc(100vh - 50px);">
      <div style="flex: 2; overflow-x: auto; padding: 1rem;">
        <div style="display: inline-block; min-width: 100%;">
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
        </div>
      </div>
      <div style="flex: 1; background: #0d1117; padding: 1rem; overflow-y: auto; border-left: 1px solid #2a2a4a;"
           id="transcript-panel">
        <h3 style="margin: 0 0 0.75rem 0; color: #64b5f6;">Transcript</h3>

        <form phx-change="select_session" style="margin-bottom: 1rem;">
          <select
            name="session_id"
            style="width: 100%; background: #1a1a2e; color: #e0e0e0; border: 1px solid #2a2a4a; border-radius: 4px; padding: 0.4rem; font-size: 0.85em;"
          >
            <option value="">Select a session...</option>
            <%= for s <- @available_sessions do %>
              <option value={s.id} selected={@session && @session.id == s.id}>
                <%= s.slug || String.slice(to_string(s.session_id), 0..7) %> - <%= if s.started_at, do: Calendar.strftime(s.started_at, "%m/%d %H:%M"), else: "?" %>
              </option>
            <% end %>
          </select>
        </form>

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
            Select a session to view its transcript.
          </p>
        <% end %>
      </div>
      <div style="flex: 1; background: #16213e; padding: 1rem; overflow-y: auto; border-left: 1px solid #2a2a4a;">
        <h3 style="margin: 0 0 1rem 0; color: #64b5f6;">Annotations</h3>

        <%= if is_nil(@session_id) do %>
          <p style="color: #888; font-style: italic;">Waiting for session...</p>
        <% else %>
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
        <% end %>
      </div>
    </div>
    """
  end

  defp type_color(:assistant), do: "color: #e0e0e0;"
  defp type_color(:user), do: "color: #7ec8e3;"
  defp type_color(_), do: "color: #888;"
end
