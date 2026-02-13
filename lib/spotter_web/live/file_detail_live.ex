defmodule SpotterWeb.FileDetailLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  import SpotterWeb.TranscriptComponents
  import SpotterWeb.AnnotationComponents

  alias Spotter.Services.FileDetail
  alias Spotter.Transcripts.{Annotation, AnnotationFileRef}

  attach_computer(SpotterWeb.Live.FileDetailComputers, :file_detail)

  @impl true
  def mount(%{"project_id" => project_id, "relative_path" => path_parts}, _session, socket) do
    relative_path = Enum.join(path_parts, "/")

    socket =
      socket
      |> assign(
        selected_text: nil,
        selection_line_start: nil,
        selection_line_end: nil
      )
      |> mount_computers(%{
        file_detail: %{project_id: project_id, relative_path: relative_path}
      })

    {:ok, socket}
  end

  @impl true
  def handle_event("select_session", %{"session-id" => session_id}, socket) do
    {:noreply, update_computer_inputs(socket, :file_detail, %{selected_session_id: session_id})}
  end

  def handle_event("file_text_selected", params, socket) do
    {:noreply,
     assign(socket,
       selected_text: params["text"],
       selection_line_start: params["line_start"],
       selection_line_end: params["line_end"]
     )}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply,
     assign(socket,
       selected_text: nil,
       selection_line_start: nil,
       selection_line_end: nil
     )}
  end

  def handle_event("save_annotation", %{"comment" => comment}, socket) do
    session_id = find_session_id(socket)

    params = %{
      session_id: session_id,
      source: :file,
      selected_text: socket.assigns.selected_text,
      comment: comment
    }

    case Ash.create(Annotation, params) do
      {:ok, annotation} ->
        create_file_ref(annotation, socket)

        {:noreply,
         socket
         |> assign(selected_text: nil, selection_line_start: nil, selection_line_end: nil)
         |> refresh_annotations()}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_annotation", %{"id" => id}, socket) do
    case Ash.get(Annotation, id) do
      {:ok, annotation} ->
        Ash.destroy!(annotation)
        {:noreply, refresh_annotations(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("highlight_annotation", %{"id" => id}, socket) do
    case Ash.get(Annotation, id, load: [:file_refs]) do
      {:ok, %{file_refs: [ref | _]}} ->
        {:noreply,
         push_event(socket, "highlight_file_lines", %{
           line_start: ref.line_start,
           line_end: ref.line_end
         })}

      _ ->
        {:noreply, socket}
    end
  end

  # No-op for transcript expand events
  def handle_event("transcript_view_toggle_tool_result_group", _params, socket) do
    {:noreply, socket}
  end

  defp find_session_id(socket) do
    case socket.assigns.file_detail_linked_sessions do
      [first | _] -> first.session.id
      _ -> nil
    end
  end

  defp create_file_ref(annotation, socket) do
    line_start = parse_line(socket.assigns.selection_line_start, 1)
    line_end = parse_line(socket.assigns.selection_line_end, line_start)

    Ash.create!(AnnotationFileRef, %{
      annotation_id: annotation.id,
      project_id: socket.assigns.file_detail_project_id,
      relative_path: socket.assigns.file_detail_relative_path,
      line_start: line_start,
      line_end: line_end
    })
  end

  defp parse_line(nil, default), do: default
  defp parse_line(val, _default) when is_integer(val), do: max(val, 1)

  defp parse_line(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> max(n, 1)
      :error -> default
    end
  end

  defp refresh_annotations(socket) do
    project_id = socket.assigns.file_detail_project_id
    path = socket.assigns.file_detail_relative_path
    annotations = FileDetail.load_file_annotations(project_id, path)
    assign(socket, file_detail_annotation_rows: annotations)
  end

  defp session_label(session) do
    session.slug || String.slice(session.session_id, 0, 8)
  end

  defp badge_text(:observed_in_session, _confidence), do: "Verified"

  defp badge_text(_type, confidence) do
    "Inferred #{round(confidence * 100)}%"
  end

  defp badge_class(:observed_in_session), do: "badge badge-verified"
  defp badge_class(_), do: "badge badge-inferred"

  defp change_type_class(:added), do: "badge badge-added"
  defp change_type_class(:deleted), do: "badge badge-deleted"
  defp change_type_class(:renamed), do: "badge badge-renamed"
  defp change_type_class(_), do: "badge badge-modified"

  defp format_timestamp(nil), do: "\u2014"

  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div data-testid="file-detail-root">
      <%= if @file_detail_not_found do %>
        <div class="breadcrumb">
          <a href="/">Dashboard</a>
          <span class="breadcrumb-sep">/</span>
          <span class="breadcrumb-current">File not found</span>
        </div>
        <div class="terminal-connecting">
          <div>
            <div class="terminal-connecting-title">File not found</div>
            <div class="terminal-connecting-subtitle">
              The requested project or file could not be found.
            </div>
          </div>
        </div>
      <% else %>
        <div class="breadcrumb">
          <a href="/">Dashboard</a>
          <span class="breadcrumb-sep">/</span>
          <a :if={@file_detail_project} href={"/projects/#{@file_detail_project_id}/heatmap"}>
            {@file_detail_project.name}
          </a>
          <span class="breadcrumb-sep">/</span>
          <span class="breadcrumb-current">{@file_detail_relative_path}</span>
        </div>

        <div class="file-detail-layout">
          <%!-- File code pane --%>
          <div class="file-detail-code" data-testid="file-code-panel">
            <div class="file-detail-header">
              <h2 class="file-detail-path">{@file_detail_relative_path}</h2>
              <span class="text-muted text-xs">
                {@file_detail_language_class}
              </span>
            </div>

            <%= if @file_detail_file_content do %>
              <div
                id="file-content-container"
                phx-hook="FileHighlighter"
                class="file-detail-content"
                data-testid="file-content"
              >
                <pre><code class={"language-#{@file_detail_language_class}"}>{@file_detail_file_content}</code></pre>
              </div>
            <% else %>
              <div class="empty-state">File content not available.</div>
            <% end %>

            <%!-- Commits touching this file --%>
            <div :if={@file_detail_commit_rows != []} class="file-detail-commits">
              <div class="file-detail-section-title">
                Commits ({length(@file_detail_commit_rows)})
              </div>
              <div :for={row <- @file_detail_commit_rows} class="file-detail-commit-row">
                <a
                  href={"/history/commits/#{row.commit.id}"}
                  class="history-commit-hash"
                >
                  {String.slice(row.commit.commit_hash, 0, 8)}
                </a>
                <span class={change_type_class(row.change_type)}>
                  {row.change_type}
                </span>
                <span class="file-detail-commit-subject">
                  {row.commit.subject || "(no subject)"}
                </span>
                <span class="text-muted text-xs">
                  {format_timestamp(row.commit.committed_at || row.commit.inserted_at)}
                </span>
              </div>
            </div>

            <%!-- Annotations --%>
            <div class="file-detail-annotations" data-testid="file-annotations">
              <div class="file-detail-section-title">Annotations</div>

              <%= if @selected_text do %>
                <.annotation_editor
                  selected_text={@selected_text}
                  selection_label={selection_label(:file, [])}
                  save_event="save_annotation"
                  clear_event="clear_selection"
                />
              <% end %>

              <.annotation_cards
                annotations={@file_detail_annotation_rows}
                highlight_event="highlight_annotation"
                delete_event="delete_annotation"
              />
            </div>
          </div>

          <%!-- Transcript panel --%>
          <div class="file-detail-transcript" data-testid="transcript-panel">
            <div class="file-detail-section-title mb-2">
              Linked Sessions ({length(@file_detail_linked_sessions)})
            </div>

            <%= if @file_detail_linked_sessions == [] do %>
              <p class="text-muted text-sm">No linked sessions.</p>
            <% else %>
              <div class="file-detail-session-list">
                <button
                  :for={entry <- @file_detail_linked_sessions}
                  phx-click="select_session"
                  phx-value-session-id={entry.session.id}
                  class={"file-detail-session-btn#{if @file_detail_selected_session_id == entry.session.id, do: " is-active"}"}
                >
                  <span class="file-detail-session-name">
                    {session_label(entry.session)}
                  </span>
                  <span :for={lt <- entry.link_types} class={badge_class(lt)}>
                    {badge_text(lt, entry.max_confidence)}
                  </span>
                </button>
              </div>

              <%= if @file_detail_selected_session_id do %>
                <div class="mt-3">
                  <.transcript_panel
                    rendered_lines={@file_detail_transcript_rendered_lines}
                    panel_id="file-transcript-messages"
                    empty_message="No transcript available for this session."
                  />
                </div>
              <% else %>
                <p class="text-muted text-sm mt-3">
                  Select a session to view its transcript.
                </p>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
