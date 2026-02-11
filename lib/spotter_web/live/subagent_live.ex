defmodule SpotterWeb.SubagentLive do
  use Phoenix.LiveView

  alias Spotter.Services.TranscriptRenderer

  alias Spotter.Transcripts.{
    Annotation,
    AnnotationMessageRef,
    Message,
    Session,
    Subagent
  }

  require Ash.Query

  @impl true
  def mount(%{"session_id" => session_id, "agent_id" => agent_id}, _session, socket) do
    case load_subagent_data(session_id, agent_id) do
      {:ok, session_record, subagent, messages, rendered_lines, annotations} ->
        socket =
          assign(socket,
            session_id: session_id,
            agent_id: agent_id,
            session_record: session_record,
            subagent: subagent,
            messages: messages,
            rendered_lines: rendered_lines,
            annotations: annotations,
            selected_text: nil,
            selection_message_ids: [],
            not_found: false
          )

        {:ok, socket}

      :not_found ->
        {:ok,
         assign(socket,
           session_id: session_id,
           agent_id: agent_id,
           not_found: true
         )}
    end
  end

  @impl true
  def handle_event("transcript_text_selected", params, socket) do
    {:noreply,
     assign(socket,
       selected_text: params["text"],
       selection_message_ids: params["message_ids"] || []
     )}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_text: nil, selection_message_ids: [])}
  end

  def handle_event("save_annotation", %{"comment" => comment}, socket) do
    params = %{
      session_id: socket.assigns.session_record.id,
      subagent_id: socket.assigns.subagent.id,
      source: :transcript,
      selected_text: socket.assigns.selected_text,
      comment: comment
    }

    case Ash.create(Annotation, params) do
      {:ok, annotation} ->
        create_message_refs(annotation, socket)

        {:noreply,
         socket
         |> assign(
           annotations: load_annotations(socket.assigns.subagent),
           selected_text: nil,
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
        {:noreply, assign(socket, annotations: load_annotations(socket.assigns.subagent))}

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

      _ ->
        {:noreply, socket}
    end
  end

  defp load_subagent_data(session_id, agent_id) do
    with {:ok, %Session{} = session_record} <-
           Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one(),
         {:ok, %Subagent{} = subagent} <-
           Subagent
           |> Ash.Query.filter(session_id == ^session_record.id and agent_id == ^agent_id)
           |> Ash.read_one() do
      messages = load_messages(subagent)
      rendered_lines = TranscriptRenderer.render(messages)
      annotations = load_annotations(subagent)
      {:ok, session_record, subagent, messages, rendered_lines, annotations}
    else
      _ -> :not_found
    end
  end

  defp load_messages(subagent) do
    Message
    |> Ash.Query.filter(subagent_id == ^subagent.id)
    |> Ash.Query.sort(timestamp: :asc)
    |> Ash.read!()
    |> Enum.map(fn msg ->
      %{
        id: msg.id,
        uuid: msg.uuid,
        type: msg.type,
        role: msg.role,
        content: msg.content,
        timestamp: msg.timestamp
      }
    end)
  end

  defp load_annotations(subagent) do
    Annotation
    |> Ash.Query.filter(subagent_id == ^subagent.id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
    |> Ash.load!(message_refs: :message)
  end

  defp create_message_refs(annotation, socket) do
    socket.assigns.selection_message_ids
    |> Enum.uniq()
    |> Enum.with_index()
    |> Enum.each(fn {msg_id, ordinal} ->
      Ash.create!(AnnotationMessageRef, %{
        annotation_id: annotation.id,
        message_id: msg_id,
        ordinal: ordinal
      })
    end)
  end

  defp type_color(:assistant), do: "color: #e0e0e0;"
  defp type_color(:user), do: "color: #7ec8e3;"
  defp type_color(_), do: "color: #888;"

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @not_found do %>
      <div class="header">
        <a href="/">&larr; Back</a>
        <span>Agent not found</span>
      </div>
      <div style="display: flex; align-items: center; justify-content: center; height: calc(100vh - 50px); color: #888;">
        <div style="text-align: center;">
          <div style="font-size: 1.2em; margin-bottom: 0.5rem;">Subagent not found</div>
          <div style="color: #555; font-size: 0.9em;">
            The requested subagent could not be found.
          </div>
        </div>
      </div>
    <% else %>
      <div class="header">
        <a href={"/sessions/#{@session_id}"}>&larr; Back to session</a>
        <span>Agent: {@subagent.slug || String.slice(@agent_id, 0, 7)}</span>
      </div>
      <div style="display: flex; gap: 0; height: calc(100vh - 50px);">
        <div style="flex: 2; background: #0d1117; padding: 1rem; overflow-y: auto;">
          <h3 style="margin: 0 0 0.75rem 0; color: #64b5f6;">Transcript</h3>

          <%= if @rendered_lines != [] do %>
            <div
              id="transcript-messages"
              phx-hook="TranscriptSelection"
              style="font-family: 'JetBrains Mono', monospace; font-size: 0.8em;"
            >
              <%= for line <- @rendered_lines do %>
                <div
                  id={"msg-#{line.line_number}"}
                  data-message-id={line.message_id}
                  style="padding: 2px 6px; border-left: 2px solid transparent;"
                >
                  <span style={type_color(line.type)}><%= line.line %></span>
                </div>
              <% end %>
            </div>
          <% else %>
            <p style="color: #666; font-style: italic; font-size: 0.85em;">
              No transcript available for this agent.
            </p>
          <% end %>
        </div>
        <div style="flex: 1; background: #16213e; padding: 1rem; overflow-y: auto; border-left: 1px solid #2a2a4a;">
          <h3 style="margin: 0 0 1rem 0; color: #64b5f6;">Annotations</h3>

          <%= if @selected_text do %>
            <div style="background: #1a1a2e; border-radius: 6px; padding: 0.75rem; margin-bottom: 1rem;">
              <div style="font-size: 0.8em; color: #888; margin-bottom: 0.5rem;">
                Selected transcript text
                <span :if={@selection_message_ids != []}>
                  ({length(@selection_message_ids)} messages)
                </span>
              </div>
              <pre style="margin: 0 0 0.75rem 0; color: #e0e0e0; white-space: pre-wrap; font-size: 0.85em; max-height: 100px; overflow-y: auto;"><%= @selected_text %></pre>
              <form phx-submit="save_annotation">
                <textarea
                  name="comment"
                  placeholder="Add a comment..."
                  required
                  style="width: 100%; min-height: 60px; background: #0d1117; color: #e0e0e0; border: 1px solid #2a2a4a; border-radius: 4px; padding: 0.5rem; font-family: inherit; resize: vertical;"
                />
                <div style="display: flex; gap: 0.5rem; margin-top: 0.5rem;">
                  <button
                    type="submit"
                    style="background: #1a6b3c; color: #e0e0e0; border: none; border-radius: 4px; padding: 0.4rem 0.8rem; cursor: pointer;"
                  >
                    Save
                  </button>
                  <button
                    type="button"
                    phx-click="clear_selection"
                    style="background: #333; color: #e0e0e0; border: none; border-radius: 4px; padding: 0.4rem 0.8rem; cursor: pointer;"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            </div>
          <% end %>

          <%= if @annotations == [] do %>
            <p style="color: #666; font-style: italic;">
              Select text in the transcript to add annotations.
            </p>
          <% end %>

          <%= for ann <- @annotations do %>
            <div
              style="background: #1a1a2e; border-radius: 6px; padding: 0.75rem; margin-bottom: 0.5rem; cursor: pointer;"
              phx-click="highlight_annotation"
              phx-value-id={ann.id}
            >
              <div style="display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.4rem;">
                <span style="color: #e0e0e0; font-size: 0.7em; padding: 1px 6px; border-radius: 3px; background: #1a4a6b;">
                  Transcript
                </span>
                <span
                  :if={ann.message_refs != []}
                  style="color: #666; font-size: 0.7em;"
                >
                  {length(ann.message_refs)} messages
                </span>
              </div>
              <pre style="margin: 0 0 0.5rem 0; color: #a0a0a0; white-space: pre-wrap; font-size: 0.8em; max-height: 60px; overflow-y: auto;"><%= ann.selected_text %></pre>
              <p style="margin: 0; color: #e0e0e0; font-size: 0.9em;"><%= ann.comment %></p>
              <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 0.5rem;">
                <span style="font-size: 0.75em; color: #555;">
                  <%= Calendar.strftime(ann.inserted_at, "%H:%M") %>
                </span>
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
    <% end %>
    """
  end
end
