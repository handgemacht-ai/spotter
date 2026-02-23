defmodule SpotterWeb.ImportModalComponents do
  @moduledoc """
  Function component for the transcript import modal dialog.
  """
  use Phoenix.Component

  attr(:show, :boolean, required: true)
  attr(:import_transcripts, :list, required: true)
  attr(:import_project_names, :list, required: true)
  attr(:import_pagination, :map, required: true)
  attr(:selected_transcripts, :any, required: true)
  attr(:importing, :boolean, required: true)
  attr(:import_errors, :list, required: true)

  def import_modal(assigns) do
    ~H"""
    <%= if @show do %>
      <div role="dialog" aria-modal="true" aria-labelledby="import-modal-title" class="import-modal-overlay" data-testid="import-modal" phx-click-away="close_import_modal" phx-window-keydown="close_import_modal" phx-key="Escape">
        <div class="import-modal-dialog">
          <div class="import-modal-header">
            <h2 id="import-modal-title">Import Transcripts</h2>
            <button aria-label="Close import modal" class="btn btn-ghost import-modal-close" phx-click="close_import_modal" data-testid="import-modal-close">&times;</button>
          </div>
          <div class="import-modal-body">
            <div class="import-modal-controls">
              <select data-testid="project-filter" phx-change="filter_import_project">
                <option value="">All Projects</option>
                <%= for name <- @import_project_names do %>
                  <option value={name}><%= name %></option>
                <% end %>
              </select>
              <select data-testid="sort-select" phx-change="sort_import_transcripts">
                <option value="last_modified">Last Updated</option>
                <option value="message_count">Message Count</option>
                <option value="project_name">Project Name</option>
              </select>
            </div>
            <%= if @import_transcripts == [] do %>
              <div class="empty-state">No transcripts found</div>
            <% else %>
              <table class="import-transcript-table">
                <thead>
                  <tr>
                    <% non_imported_paths = @import_transcripts |> Enum.reject(& &1.already_imported) |> Enum.map(& &1.file_path) |> MapSet.new() %>
                    <th><input type="checkbox" data-testid="select-all" phx-click="toggle_select_all" checked={MapSet.size(non_imported_paths) > 0 and MapSet.subset?(non_imported_paths, @selected_transcripts)} /></th>
                    <th>Project</th>
                    <th>Messages</th>
                    <th>Team</th>
                    <th>Last Updated</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for t <- @import_transcripts do %>
                    <tr data-testid="transcript-row" data-first-prompt={t[:first_prompt]} class={if t.already_imported, do: "already-imported", else: ""}>
                      <td>
                        <input type="checkbox" data-testid="select-transcript" value={t.file_path} phx-click="toggle_select_transcript" phx-value-path={t.file_path} {if t.already_imported, do: [disabled: "disabled"], else: []} />
                      </td>
                      <td><%= t.project_name %></td>
                      <td><%= t.message_count %></td>
                      <td><%= if t.is_team_session, do: "●" %></td>
                      <td><%= relative_time(t.last_modified) %></td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
            <%= if @import_pagination.total_count > @import_pagination.per_page do %>
              <nav data-testid="pagination">
                <%= for page <- 1..ceil(@import_pagination.total_count / @import_pagination.per_page) do %>
                  <button data-testid={"page-#{page}"} phx-click="import_page" phx-value-page={page} aria-current={if page == @import_pagination.page, do: "page"}><%= page %></button>
                <% end %>
              </nav>
            <% end %>
            <%= if @import_errors != [] do %>
              <div class="import-errors">
                <%= for err <- @import_errors do %>
                  <div class="import-error-item"><%= err.reason %></div>
                <% end %>
              </div>
            <% end %>
          </div>
          <div class="import-modal-footer">
            <%= if MapSet.size(@selected_transcripts) > 0 do %>
              <div data-testid="selection-count"><%= MapSet.size(@selected_transcripts) %> selected</div>
            <% end %>
            <button data-testid="import-action-button" class={"btn#{if MapSet.size(@selected_transcripts) > 0, do: " btn-primary"}"} phx-click="import_selected" {if MapSet.size(@selected_transcripts) == 0, do: [disabled: "disabled"], else: []}>
              <%= if MapSet.size(@selected_transcripts) > 0 do %>Import <%= MapSet.size(@selected_transcripts) %><% else %>Import<% end %>
            </button>
            <%= if @importing do %>
              <div data-testid="import-progress">Importing...</div>
            <% end %>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp relative_time(nil), do: "\u2014"

  defp relative_time(dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end
end
