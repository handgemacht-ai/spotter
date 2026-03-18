defmodule SpotterWeb.FolderViewLive do
  @moduledoc "LiveView for inline folder viewing with annotation support."
  use Phoenix.LiveView

  require OpenTelemetry.Tracer, as: Tracer

  import SpotterWeb.FolderComponents
  import SpotterWeb.AnnotationComponents

  alias Spotter.Services.FileDetail
  alias Spotter.Services.SkillFolderReader
  alias Spotter.Transcripts.{Annotation, AnnotationFileRef}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       folder_path: nil,
       folder_type: nil,
       rendered_files: [],
       annotations: [],
       selected_text: nil,
       selection_file_path: nil,
       selection_line_start: nil,
       selection_line_end: nil,
       page_title: "Folder View"
     )}
  end

  @impl true
  def handle_params(%{"folder_path" => path_segments, "project_id" => project_id}, _uri, socket) do
    if Enum.any?(path_segments, &(&1 == "..")) do
      {:noreply, push_navigate(socket, to: "/")}
    else
      socket =
        if connected?(socket) do
          load_folder(socket, project_id, path_segments)
        else
          assign(socket, page_title: Path.join(path_segments))
        end

      {:noreply, socket}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "folder_text_selected",
        %{"file_path" => file_path, "selected_text" => text} = params,
        socket
      ) do
    {:noreply,
     assign(socket,
       selected_text: String.slice(text, 0, 500),
       selection_file_path: file_path,
       selection_line_start: params["line_start"],
       selection_line_end: params["line_end"]
     )}
  end

  @impl true
  def handle_event("save_annotation", %{"comment" => comment} = params, socket) do
    socket =
      if socket.assigns.selected_text do
        case do_save_annotation(socket, comment, params["purpose"] || "review") do
          {:ok, _} ->
            socket
            |> clear_selection()
            |> assign(
              annotations:
                load_folder_annotations(
                  socket.assigns.current_project_id,
                  socket.assigns.rendered_files
                )
            )

          {:error, _} ->
            socket |> clear_selection() |> put_flash(:error, "Could not save annotation.")
        end
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_annotation", %{"id" => id}, socket) do
    Tracer.with_span "spotter.folder_view.delete_annotation" do
      Tracer.set_attribute("spotter.annotation.id", id)

      project_id = socket.assigns.current_project_id

      case Annotation |> Ash.get(id, load: [:file_refs]) do
        {:ok, %{source: :file, project_id: ^project_id} = annotation} ->
          try do
            Enum.each(annotation.file_refs, &Ash.destroy!/1)
            Ash.destroy!(annotation)
            annotations = Enum.reject(socket.assigns.annotations, &(&1.id == id))
            {:noreply, assign(socket, annotations: annotations)}
          rescue
            _ ->
              Tracer.set_status(:error, "delete_failed")
              {:noreply, put_flash(socket, :error, "Could not delete annotation.")}
          end

        _ ->
          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, clear_selection(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="folder-view-container" data-testid="folder-view-root">
      <div class="page-header">
        <.link
          patch={"/repo?project=#{URI.encode_www_form(@current_project_id || "")}"}
          class="plan-back-link"
          data-testid="back-to-repo"
        >
          &larr; Back to Repo Tree
        </.link>
        <h1 class="folder-view-title">
          {@folder_path || "Folder"}
          <span :if={@folder_type && @folder_type != :custom} class={"badge badge-#{folder_badge_class(@folder_type)}"}>
            {folder_badge_label(@folder_type)}
          </span>
        </h1>
      </div>

      <div class="folder-view-layout">
        <div
          class="folder-content"
          id="folder-content"
          phx-hook="FolderContentHook"
          data-testid="folder-content"
        >
          <%= if @rendered_files == [] do %>
            <div class="empty-state" data-testid="folder-empty">
              This folder is empty.
            </div>
          <% else %>
            <.folder_section
              :for={file <- @rendered_files}
              file={file}
              project_id={@current_project_id}
            />
          <% end %>
        </div>

        <div class="folder-annotations-sidebar" data-testid="folder-annotations">
          <h3>Annotations ({length(@annotations)})</h3>
          <.annotation_cards
            annotations={@annotations}
            delete_event="delete_annotation"
            empty_message="No annotations yet. Select text to annotate."
          />
        </div>
      </div>

      <%= if @selected_text do %>
        <div data-testid="folder-annotation-form">
          <.annotation_editor
            selected_text={@selected_text}
            selection_label={"Selected from #{@selection_file_path}"}
            save_event="save_annotation"
            clear_event="clear_selection"
          />
        </div>
      <% end %>
    </div>
    """
  end

  defp folder_badge_class(:agent_memory), do: "memory"
  defp folder_badge_class(_), do: "skill"

  defp folder_badge_label(:agent_memory), do: "MEMORY"
  defp folder_badge_label(:design_skill), do: "SKILL"
  defp folder_badge_label(:product_skill), do: "SKILL"
  defp folder_badge_label(:claude_rules), do: "RULES"
  defp folder_badge_label(_), do: "FOLDER"

  defp clear_selection(socket) do
    assign(socket,
      selected_text: nil,
      selection_file_path: nil,
      selection_line_start: nil,
      selection_line_end: nil
    )
  end

  defp load_folder(socket, project_id, path_segments) do
    folder_path = Path.join(path_segments)

    Tracer.with_span "spotter.folder_view.load",
                     %{attributes: %{"folder.path" => folder_path}} do
      result =
        with {:ok, repo_root} <- FileDetail.resolve_repo_root(project_id),
             folder_type = SkillFolderReader.classify_folder(folder_path),
             {:ok, rendered_files} <- SkillFolderReader.render_folder(repo_root, folder_path) do
          annotations = load_folder_annotations(project_id, rendered_files)

          Tracer.set_attribute("folder.file_count", length(rendered_files))
          Tracer.set_attribute("folder.annotation_count", length(annotations))

          {:ok, folder_type, rendered_files, annotations}
        end

      case result do
        {:ok, folder_type, rendered_files, annotations} ->
          assign(socket,
            folder_path: folder_path,
            folder_type: folder_type,
            rendered_files: rendered_files,
            annotations: annotations,
            page_title: folder_path
          )

        {:error, reason} ->
          Tracer.set_status(:error, to_string(reason))
          assign_empty_folder(socket, folder_path)
      end
    end
  end

  defp assign_empty_folder(socket, folder_path) do
    assign(socket,
      folder_path: folder_path,
      folder_type: :custom,
      rendered_files: [],
      annotations: [],
      page_title: folder_path
    )
  end

  defp load_folder_annotations(project_id, rendered_files) do
    Enum.flat_map(rendered_files, fn file ->
      FileDetail.load_file_annotations(project_id, file.relative_path)
    end)
  end

  defp do_save_annotation(socket, comment, purpose) do
    Tracer.with_span "spotter.folder_view.create_annotation" do
      %{
        current_project_id: project_id,
        selected_text: text,
        selection_file_path: file_path,
        selection_line_start: line_start,
        selection_line_end: line_end
      } = socket.assigns

      Tracer.set_attribute("spotter.annotation.file_path", file_path)

      purpose_atom =
        case purpose do
          "explain" -> :explain
          _ -> :review
        end

      case Annotation
           |> Ash.Changeset.for_create(:create, %{
             project_id: project_id,
             source: :file,
             selected_text: text,
             comment: comment,
             purpose: purpose_atom,
             relative_path: file_path,
             line_start: line_start,
             line_end: line_end
           })
           |> Ash.create() do
        {:ok, annotation} ->
          case AnnotationFileRef
               |> Ash.Changeset.for_create(:create, %{
                 annotation_id: annotation.id,
                 project_id: project_id,
                 relative_path: file_path,
                 line_start: line_start,
                 line_end: line_end
               })
               |> Ash.create() do
            {:ok, _ref} ->
              {:ok, annotation}

            {:error, reason} ->
              Ash.destroy(annotation)
              Tracer.set_status(:error, inspect(reason))
              {:error, reason}
          end

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          {:error, reason}
      end
    end
  end
end
