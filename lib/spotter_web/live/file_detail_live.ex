defmodule SpotterWeb.FileDetailLive do
  use Phoenix.LiveView
  use AshComputer.LiveView

  import SpotterWeb.TranscriptComponents
  import SpotterWeb.AnnotationComponents

  alias Spotter.Services.{ExplainAnnotations, FileDetail}
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
        selection_line_end: nil,
        explain_streams: %{},
        active_sidebar_tab: :annotations,
        highlight_line_start: nil,
        highlight_line_end: nil,
        highlight_hotspot_id: nil,
        highlight_annotation_id: nil
      )
      |> mount_computers(%{
        file_detail: %{project_id: project_id, relative_path: relative_path}
      })

    {:ok, socket}
  end

  @impl true
  def handle_params(
        %{"project_id" => project_id, "relative_path" => path_parts} = params,
        _uri,
        socket
      )
      when is_list(path_parts) do
    relative_path = Enum.join(path_parts, "/")
    {line_start, line_end} = parse_line_range(params)

    socket =
      socket
      |> mount_computers(%{
        file_detail: %{project_id: project_id, relative_path: relative_path}
      })
      |> assign(
        selected_text: nil,
        selection_line_start: nil,
        selection_line_end: nil,
        highlight_line_start: line_start,
        highlight_line_end: line_end,
        highlight_hotspot_id: params["hotspot_id"],
        highlight_annotation_id: params["annotation_id"]
      )
      |> maybe_push_highlight(line_start, line_end)

    {:noreply, socket}
  end

  @impl true
  def handle_params(%{"project_id" => project_id}, _uri, socket) do
    socket =
      socket
      |> mount_computers(%{
        file_detail: %{project_id: project_id, relative_path: nil}
      })
      |> assign(
        selected_text: nil,
        selection_line_start: nil,
        selection_line_end: nil,
        highlight_line_start: nil,
        highlight_line_end: nil,
        highlight_hotspot_id: nil,
        highlight_annotation_id: nil
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_session", %{"session-id" => session_id}, socket) do
    {:noreply, update_computer_inputs(socket, :file_detail, %{selected_session_id: session_id})}
  end

  def handle_event("toggle_view_mode", %{"mode" => mode}, socket) do
    view_mode = if mode == "raw", do: :raw, else: :blame
    {:noreply, update_computer_inputs(socket, :file_detail, %{view_mode: view_mode})}
  end

  def handle_event("switch_sidebar_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_sidebar_tab: String.to_existing_atom(tab))}
  end

  def handle_event("clear_highlight", _params, socket) do
    project_id = socket.assigns.file_detail_project_id
    relative_path = socket.assigns.file_detail_relative_path
    url = "/projects/#{project_id}/files/#{relative_path}"

    {:noreply,
     socket
     |> assign(
       highlight_line_start: nil,
       highlight_line_end: nil,
       highlight_hotspot_id: nil,
       highlight_annotation_id: nil
     )
     |> push_patch(to: url)}
  end

  def handle_event("file_text_selected", params, socket) do
    socket =
      assign(socket,
        selected_text: params["text"],
        selection_line_start: params["line_start"],
        selection_line_end: params["line_end"]
      )

    socket =
      if socket.assigns.active_sidebar_tab != :annotations do
        socket
        |> assign(active_sidebar_tab: :annotations)
        |> push_event("annotations_attention", %{})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply,
     assign(socket,
       selected_text: nil,
       selection_line_start: nil,
       selection_line_end: nil
     )}
  end

  def handle_event("save_annotation", params, socket) do
    session_id = socket.assigns.file_detail_selected_session_id

    if is_nil(session_id) do
      {:noreply,
       put_flash(socket, :error, "Select a linked session before saving an annotation.")}
    else
      comment = params["comment"] || ""
      purpose = if params["purpose"] == "explain", do: :explain, else: :review
      line_start = parse_line(socket.assigns.selection_line_start, 1)
      line_end = parse_line(socket.assigns.selection_line_end, line_start)

      create_params = %{
        session_id: session_id,
        project_id: socket.assigns.file_detail_project_id,
        source: :file,
        selected_text: socket.assigns.selected_text,
        comment: comment,
        purpose: purpose,
        relative_path: socket.assigns.file_detail_relative_path,
        line_start: line_start,
        line_end: line_end
      }

      case Ash.create(Annotation, create_params) do
        {:ok, annotation} ->
          create_file_ref(annotation, socket)
          socket = maybe_enqueue_explain(socket, annotation, purpose)

          {:noreply,
           socket
           |> assign(selected_text: nil, selection_line_start: nil, selection_line_end: nil)
           |> refresh_annotations()}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save annotation.")}
      end
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

  def handle_event("transcript_view_toggle_hook_group", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:annotation_explain_delta, id, chunk}, socket) do
    streams = socket.assigns.explain_streams
    current = Map.get(streams, id, "")
    {:noreply, assign(socket, explain_streams: Map.put(streams, id, current <> chunk))}
  end

  def handle_info({:annotation_explain_done, _id, _final, _refs}, socket) do
    {:noreply, socket |> assign(explain_streams: %{}) |> refresh_annotations()}
  end

  def handle_info({:annotation_explain_error, _id, _reason}, socket) do
    {:noreply, socket |> assign(explain_streams: %{}) |> refresh_annotations()}
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

  defp format_blame_error(:git_blame_failed), do: "git blame command failed."
  defp format_blame_error(other), do: inspect(other)

  defp format_file_error(:no_accessible_cwd),
    do: "No accessible working directory found for this project."

  defp format_file_error(:git_root_failed), do: "Could not resolve git repository root."
  defp format_file_error({:file_read_failed, reason, path}), do: "#{inspect(reason)} — #{path}"
  defp format_file_error(other), do: inspect(other)

  defp format_timestamp(nil), do: "\u2014"

  defp format_timestamp(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp short_hash(nil), do: "unknown"
  defp short_hash(hash) when is_binary(hash) and byte_size(hash) > 8, do: String.slice(hash, 0, 8)
  defp short_hash(hash), do: hash

  defp short_session_id(nil), do: "unknown"

  defp short_session_id(session_id) when is_binary(session_id) and byte_size(session_id) > 8,
    do: String.slice(session_id, 0, 8)

  defp short_session_id(session_id), do: session_id

  defp parse_line_range(params) do
    line_start = parse_pos_int(params["line_start"])
    line_end = parse_pos_int(params["line_end"])

    cond do
      line_start && line_end && line_end >= line_start -> {line_start, line_end}
      line_start -> {line_start, line_start}
      true -> {nil, nil}
    end
  end

  defp parse_pos_int(nil), do: nil

  defp parse_pos_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} when n >= 1 -> n
      _ -> nil
    end
  end

  defp parse_pos_int(_), do: nil

  defp maybe_push_highlight(socket, nil, _), do: socket

  defp maybe_push_highlight(socket, line_start, line_end) do
    socket
    |> update_computer_inputs(:file_detail, %{view_mode: :blame})
    |> push_event("highlight_file_lines", %{line_start: line_start, line_end: line_end})
  end

  defp path_label(nil), do: "/"
  defp path_label(""), do: "Root"
  defp path_label(path), do: path

  defp directory_parent(nil), do: nil
  defp directory_parent(""), do: nil

  defp directory_parent(relative_path) do
    parts = String.split(relative_path, "/", trim: true)

    if length(parts) <= 1 do
      ""
    else
      parts |> Enum.drop(-1) |> Enum.join("/")
    end
  end

  defp file_detail_url(project_id, nil), do: "/projects/#{project_id}/files"
  defp file_detail_url(project_id, ""), do: "/projects/#{project_id}/files"

  defp file_detail_url(project_id, relative_path),
    do: "/projects/#{project_id}/files/#{relative_path}"

  defp path_segments(nil), do: []
  defp path_segments(""), do: []

  defp path_segments(relative_path) do
    parts = String.split(relative_path, "/", trim: true)
    total = length(parts)

    Enum.with_index(parts, 0)
    |> Enum.map(fn {part, index} ->
      %{
        name: part,
        relative_path: Enum.join(Enum.take(parts, index + 1), "/"),
        is_last: index == total - 1
      }
    end)
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
          <%= if @file_detail_is_directory do %>
            <%= if path_segments(@file_detail_relative_path) == [] do %>
              <span class="breadcrumb-current">Root</span>
            <% else %>
              <%= for segment <- path_segments(@file_detail_relative_path) do %>
                <%= if !segment.is_last do %>
                  <a
                    href={file_detail_url(@file_detail_project_id, segment.relative_path)}
                    phx-link="patch"
                    phx-link-state="push"
                  >
                    {segment.name}
                  </a>
                  <span class="breadcrumb-sep">/</span>
                <% else %>
                  <span class="breadcrumb-current">{segment.name}</span>
                <% end %>
              <% end %>
            <% end %>
          <% else %>
            <a href={file_detail_url(@file_detail_project_id, "")} phx-link="patch" phx-link-state="push">
              Root
            </a>
            <span class="breadcrumb-sep">/</span>
            <%= if path_segments(@file_detail_relative_path) == [] do %>
              <span class="breadcrumb-current">File</span>
            <% else %>
              <%= for segment <- path_segments(@file_detail_relative_path) do %>
                <%= if !segment.is_last do %>
                  <a
                    href={file_detail_url(@file_detail_project_id, segment.relative_path)}
                    phx-link="patch"
                    phx-link-state="push"
                  >
                    {segment.name}
                  </a>
                  <span class="breadcrumb-sep">/</span>
                <% else %>
                  <span class="breadcrumb-current">{segment.name}</span>
                <% end %>
              <% end %>
            <% end %>
          <% end %>
        </div>

        <div class="file-detail-layout">
          <%!-- File code pane --%>
          <div class="file-detail-code" data-testid="file-code-panel">
            <div class="file-detail-header">
              <h2 class="file-detail-path">
                <%= if @file_detail_is_directory do %>
                  {path_label(@file_detail_relative_path)}
                <% else %>
                  <%= if path_segments(@file_detail_relative_path) == [] do %>
                    File
                  <% else %>
                    <%= for segment <- path_segments(@file_detail_relative_path) do %>
                      <%= if !segment.is_last do %>
                        <a
                          href={file_detail_url(@file_detail_project_id, segment.relative_path)}
                          phx-link="patch"
                          phx-link-state="push"
                          class="file-detail-path-link"
                        >
                          {segment.name}
                        </a>
                        <span class="breadcrumb-sep">/</span>
                      <% else %>
                        <span>{segment.name}</span>
                      <% end %>
                    <% end %>
                  <% end %>
                <% end %>
              </h2>
              <%= if @file_detail_is_directory do %>
                <span class="text-muted text-xs">Folder</span>
              <% else %>
                <span class="text-muted text-xs">
                  {@file_detail_language_class}
                </span>
                <div class="filter-bar ml-auto" data-testid="view-mode-toggle">
                  <button
                    phx-click="toggle_view_mode"
                    phx-value-mode="blame"
                    class={"filter-btn#{if @file_detail_view_mode == :blame, do: " is-active"}"}
                  >
                    Blame
                  </button>
                  <button
                    phx-click="toggle_view_mode"
                    phx-value-mode="raw"
                    class={"filter-btn#{if @file_detail_view_mode == :raw, do: " is-active"}"}
                  >
                    Raw
                  </button>
                </div>
              <% end %>
            </div>

            <%= if @highlight_line_start do %>
              <div class="file-highlight-banner">
                <span>Highlighted lines {@highlight_line_start}-{@highlight_line_end}</span>
                <button phx-click="clear_highlight" class="file-highlight-clear">Clear</button>
              </div>
            <% end %>

            <%= if @file_detail_is_directory do %>
              <div class="file-detail-folder-view">
                <div :if={directory_parent(@file_detail_relative_path) != nil} class="file-detail-folder-list">
                <a
                  phx-link="patch"
                  phx-link-state="push"
                  class="file-detail-folder-row file-detail-folder-up"
                  href={file_detail_url(@file_detail_project_id, directory_parent(@file_detail_relative_path))}
                >
                    <span class="file-detail-folder-kind">↩</span>
                    <span class="file-detail-folder-name">..</span>
                  </a>
                </div>

                <%= if @file_detail_directory_entries == [] do %>
                  <div class="empty-state text-muted text-sm">This folder is empty.</div>
                <% else %>
                  <div class="file-detail-folder-list">
                    <a
                      :for={entry <- @file_detail_directory_entries}
                      href={file_detail_url(@file_detail_project_id, entry.relative_path)}
                      phx-link="patch"
                      phx-link-state="push"
                      class={"file-detail-folder-row file-detail-folder-#{if entry.kind == :directory, do: "directory", else: "file"}"}
                    >
                      <span class="file-detail-folder-kind">
                        <%= if entry.kind == :directory, do: "📁", else: "📄" %>
                      </span>
                      <span class="file-detail-folder-name">{entry.name}</span>
                    </a>
                  </div>
                <% end %>
              </div>
            <% else %>
              <%= if @file_detail_view_mode == :blame do %>
                <%= if @file_detail_blame_rows do %>
                  <div
                    id="file-blame-container"
                    class="file-detail-blame"
                    data-testid="blame-view"
                    phx-hook="FileHighlighter"
                  >
                    <div class="blame-lines">
                      <div :for={row <- @file_detail_blame_rows} class={"blame-line blame-session-band--#{row.session_band}"} data-line-no={row.line_no}>
                        <div class="blame-gutter">
                          <a
                            :if={row.commit_id}
                            href={"/history/commits/#{row.commit_id}"}
                            class="blame-meta-link blame-commit-link"
                            title={"Commit " <> (row.commit_hash || "")}
                          >
                            <span class="blame-meta-kind">commit:</span>
                            <span class="blame-meta-value">{short_hash(row.commit_hash)}</span>
                          </a>
                          <a
                            :if={row.session_link}
                            href={"/sessions/#{row.session_link.session_id}"}
                            class="blame-meta-link blame-session-link"
                            title={"Session " <> (row.session_link.session_id || "")}
                          >
                            <span class="blame-meta-kind">session:</span>
                            <span class="blame-meta-value">{short_session_id(row.session_link.session_id)}</span>
                          </a>
                        </div>
                        <div class="blame-line-main">
                          <span class="blame-line-no">{row.line_no}</span>
                          <pre class="blame-code"><code class={"language-#{@file_detail_language_class}"}>{row.text}</code></pre>
                        </div>
                      </div>
                    </div>
                  </div>
                <% else %>
                  <div class="empty-state" data-testid="blame-error">
                    <p>Blame not available.</p>
                    <p :if={@file_detail_blame_error} class="text-muted text-sm">
                      {format_blame_error(@file_detail_blame_error)}
                    </p>
                  </div>
                <% end %>
              <% else %>
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
                  <div class="empty-state" data-testid="file-error">
                    <p>File content not available.</p>
                    <div :if={@file_detail_file_error} class="text-muted text-sm mt-2">
                      <p>
                        <strong>Reason:</strong> {format_file_error(@file_detail_file_error)}
                      </p>
                      <p :if={@file_detail_repo_root}>
                        <strong>Repo root:</strong> {@file_detail_repo_root}
                      </p>
                      <p>
                        <strong>Requested path:</strong> {@file_detail_relative_path}
                      </p>
                    </div>
                  </div>
                <% end %>
                <% end %>
              <% end %>

          </div>

          <%!-- RHS Tabbed Sidebar --%>
          <div class="file-detail-sidebar" data-testid="file-sidebar">
            <%= if @file_detail_is_directory do %>
              <div class="sidebar-tab-content">
                <div class="file-detail-section-title mb-2">Folder mode</div>
                <p class="text-muted text-sm">
                  Open a file to view blame, commits, and linked sessions.
                </p>
              </div>
            <% else %>
              <div class="sidebar-tabs">
                <button
                  id="sidebar-tab-annotations"
                  class={"sidebar-tab#{if @active_sidebar_tab == :annotations, do: " is-active"}"}
                  phx-click="switch_sidebar_tab"
                  phx-value-tab="annotations"
                >
                  Annotations ({length(@file_detail_annotation_rows)})
                </button>
                <button
                  class={"sidebar-tab#{if @active_sidebar_tab == :sessions, do: " is-active"}"}
                  phx-click="switch_sidebar_tab"
                  phx-value-tab="sessions"
                >
                  Sessions ({length(@file_detail_linked_sessions)})
                </button>
                <button
                  class={"sidebar-tab#{if @active_sidebar_tab == :commits, do: " is-active"}"}
                  phx-click="switch_sidebar_tab"
                  phx-value-tab="commits"
                >
                  Commits ({length(@file_detail_commit_rows)})
                </button>
              </div>

              <%!-- Annotations tab --%>
              <div :if={@active_sidebar_tab == :annotations} class="sidebar-tab-content" data-testid="file-annotations">
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
                  explain_streams={@explain_streams}
                  highlight_event="highlight_annotation"
                  delete_event="delete_annotation"
                />
              </div>

              <%!-- Sessions tab --%>
              <div :if={@active_sidebar_tab == :sessions} class="sidebar-tab-content">
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

              <%!-- Commits tab --%>
              <div :if={@active_sidebar_tab == :commits} class="sidebar-tab-content">
                <%= if @file_detail_commit_rows == [] do %>
                  <p class="text-muted text-sm">No commits for this file.</p>
                <% else %>
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
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
