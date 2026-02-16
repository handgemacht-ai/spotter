defmodule SpotterWeb.SubagentLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  import SpotterWeb.TranscriptComponents
  import SpotterWeb.AnnotationComponents

  alias Spotter.Services.{ExplainAnnotations, ReviewUpdates, TranscriptFileLinks}

  alias Spotter.Transcripts.{
    Annotation,
    AnnotationMessageRef,
    Message,
    Session,
    Subagent
  }

  require Ash.Query

  attach_computer(SpotterWeb.Live.TranscriptComputers, :transcript_view)

  @impl true
  def mount(%{"session_id" => session_id, "agent_id" => agent_id}, _session, socket) do
    case load_subagent_data(session_id, agent_id) do
      {:ok, session_record, subagent, messages, annotations} ->
        session_cwd = session_record.cwd
        {link_project_id, link_fileset} = resolve_file_link_context(session_record)

        socket =
          socket
          |> assign(
            session_id: session_id,
            agent_id: agent_id,
            session_record: session_record,
            subagent: subagent,
            annotations: annotations,
            selected_text: nil,
            selection_message_ids: [],
            explain_streams: %{},
            not_found: false,
            transcript_link_project_id: link_project_id,
            transcript_link_fileset: link_fileset
          )
          |> mount_computers(%{
            transcript_view: %{messages: messages, session_cwd: session_cwd}
          })

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
    socket =
      socket
      |> assign(
        selected_text: params["text"],
        selection_message_ids: params["message_ids"] || []
      )
      |> push_event("annotations_attention", %{})

    {:noreply, socket}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selected_text: nil, selection_message_ids: [])}
  end

  def handle_event("save_annotation", params, socket) do
    comment = params["comment"] || ""
    purpose = if params["purpose"] == "explain", do: :explain, else: :review

    create_params = %{
      session_id: socket.assigns.session_record.id,
      subagent_id: socket.assigns.subagent.id,
      source: :transcript,
      selected_text: socket.assigns.selected_text,
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
        ReviewUpdates.broadcast_counts()
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

  def handle_event("toggle_debug", _params, socket) do
    new_debug = !socket.assigns.transcript_view_show_debug
    {:noreply, update_computer_inputs(socket, :transcript_view, %{show_debug: new_debug})}
  end

  # No-op handler for subagent badge clicks (subagents don't navigate further)
  def handle_event("subagent_reference_clicked", _params, socket) do
    {:noreply, socket}
  end

  @impl true
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
       annotations: load_annotations(socket.assigns.subagent)
     )}
  end

  def handle_info({:annotation_explain_error, id, _reason}, socket) do
    streams = Map.delete(socket.assigns.explain_streams, id)

    {:noreply,
     socket
     |> assign(
       explain_streams: streams,
       annotations: load_annotations(socket.assigns.subagent)
     )}
  end

  defp maybe_enqueue_explain(socket, annotation, :explain) do
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

  defp resolve_file_link_context(session_record) do
    project_id = to_string(session_record.project_id)

    case TranscriptFileLinks.for_session(session_record.cwd) do
      {:ok, %{files: files}} -> {project_id, files}
      {:error, _} -> {project_id, nil}
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
      annotations = load_annotations(subagent)
      {:ok, session_record, subagent, messages, annotations}
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
        raw_payload: msg.raw_payload,
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

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @not_found do %>
      <div class="breadcrumb">
        <a href="/">Dashboard</a>
        <span class="breadcrumb-sep">/</span>
        <span class="breadcrumb-current">Agent not found</span>
      </div>
      <div class="terminal-connecting">
        <div>
          <div class="terminal-connecting-title">Subagent not found</div>
          <div class="terminal-connecting-subtitle">
            The requested subagent could not be found.
          </div>
        </div>
      </div>
    <% else %>
      <div class="breadcrumb">
        <a href="/">Dashboard</a>
        <span class="breadcrumb-sep">/</span>
        <a href={"/sessions/#{@session_id}"}>Session {String.slice(@session_id, 0, 7)}</a>
        <span class="breadcrumb-sep">/</span>
        <span class="breadcrumb-current">Agent {@subagent.slug || String.slice(@agent_id, 0, 7)}</span>
      </div>
      <div class="session-layout">
        <div class="session-transcript" id="transcript-panel">
          <div class="transcript-header">
            <h3>Transcript</h3>
          </div>

          <.transcript_panel
            rendered_lines={@transcript_view_visible_lines}
            all_rendered_lines={@transcript_view_rendered_lines}
            expanded_tool_groups={@transcript_view_expanded_tool_groups}
            expanded_hook_groups={@transcript_view_expanded_hook_groups}
            session_id={@session_id}
            current_agent_id={@agent_id}
            show_debug={@transcript_view_show_debug}
            project_id={@transcript_link_project_id}
            existing_files={@transcript_link_fileset}
            empty_message="No transcript available for this agent."
          />
        </div>
        <div class="session-sidebar">
          <div class="sidebar-tab-content">
            <h3 class="mb-4">Annotations</h3>

            <.annotation_editor
              :if={@selected_text}
              selected_text={@selected_text}
              selection_label={selection_label(:transcript, @selection_message_ids)}
            />

            <.annotation_cards
              annotations={@annotations}
              explain_streams={@explain_streams}
              empty_message="Select text in the transcript to add annotations."
            />
          </div>
        </div>
      </div>
    <% end %>
    """
  end
end
