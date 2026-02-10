defmodule SpotterWeb.PaneViewLive do
  use Phoenix.LiveView

  alias Spotter.Services.Tmux
  alias Spotter.Transcripts.Annotation
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

    annotations = load_annotations(pane_id)

    {:ok,
     assign(socket,
       pane_id: pane_id,
       cols: cols,
       rows: rows,
       annotations: annotations,
       selected_text: nil,
       selection_start_row: nil,
       selection_start_col: nil,
       selection_end_row: nil,
       selection_end_col: nil
     )}
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
      pane_id: socket.assigns.pane_id,
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
           annotations: load_annotations(socket.assigns.pane_id),
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

        {:noreply, assign(socket, annotations: load_annotations(socket.assigns.pane_id))}

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

  defp load_annotations(pane_id) do
    Annotation
    |> Ash.Query.filter(pane_id == ^pane_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="header">
      <a href="/">&larr; Back</a>
      <span>Pane: {@pane_id}</span>
    </div>
    <div style="display: flex; gap: 0; height: calc(100vh - 50px);">
      <div style="flex: 1; overflow-x: auto; padding: 1rem;">
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
      <div style="flex: 1; background: #16213e; padding: 1rem; overflow-y: auto; border-left: 1px solid #2a2a4a;">
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
end
