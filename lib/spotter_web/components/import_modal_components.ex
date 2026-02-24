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
                  <option value={name}><%= format_project_name(name) %></option>
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
              <%
                non_imported_paths = @import_transcripts |> Enum.reject(& &1.already_imported) |> Enum.map(& &1.file_path) |> MapSet.new()
                # Compute which team names should show Import Team button (first non-imported occurrence only)
                teams_with_btn = first_team_occurrences(@import_transcripts)
              %>
              <table class="import-transcript-table">
                <thead>
                  <tr>
                    <th><input type="checkbox" data-testid="select-all" phx-click="toggle_select_all" checked={MapSet.size(non_imported_paths) > 0 and MapSet.subset?(non_imported_paths, @selected_transcripts)} /></th>
                    <th>Session</th>
                    <th>Project</th>
                    <th>Messages</th>
                    <th>Agent</th>
                    <th>Team</th>
                    <th>Last Updated</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for t <- @import_transcripts do %>
                    <tr data-testid="transcript-row" data-first-prompt={t[:first_prompt]} class={if t.already_imported, do: "already-imported", else: ""}>
                      <td>
                        <input type="checkbox" data-testid="select-transcript" value={t.file_path} phx-click="toggle_select_transcript" phx-value-path={t.file_path} checked={MapSet.member?(@selected_transcripts, t.file_path)} {if t.already_imported, do: [disabled: "disabled"], else: []} />
                      </td>
                      <td class="import-session-label" title={t[:first_prompt]}><%= session_label(t) %></td>
                      <td><%= format_project_name(t.project_name) %></td>
                      <td><%= t.message_count %></td>
                      <td><%= t[:agent_name] %></td>
                      <td>
                        <%= if t.is_team_session do %>
                          <span class="team-badge" data-testid="team-badge" data-team-name={t[:team_name]}>
                            ● <%= t[:team_name] %>
                          </span>
                          <%= if MapSet.member?(teams_with_btn, t.file_path) do %>
                            <button
                              class="btn btn-ghost btn-xs import-team-btn"
                              data-testid="import-team-btn"
                              phx-click="import_team"
                              phx-value-team-name={t[:team_name]}
                            >
                              Import Team
                            </button>
                          <% end %>
                        <% end %>
                      </td>
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

  @max_label_length 60

  defp session_label(t) do
    non_empty(t[:custom_title]) ||
      non_empty(t[:summary]) ||
      truncate_text(t[:first_prompt]) ||
      short_id(t[:session_id])
  end

  defp format_project_name(name) when is_binary(name) do
    # Raw dir names encode full paths: "-home-marco-projects-handgemacht-spotter"
    # Recover path, then extract from the last "projects" directory onward
    path =
      name
      |> String.replace_leading("-", "/")
      |> String.replace("-", "/")

    case String.split(path, "/projects/") do
      [_, after_projects] when after_projects != "" ->
        after_projects

      _ ->
        # No /projects/ segment — take last 2 path segments for context
        segments = path |> Path.split() |> Enum.reject(&(&1 == "/"))

        case segments do
          [] -> name
          [single] -> single
          parts -> parts |> Enum.take(-2) |> Enum.join("/")
        end
    end
  end

  defp format_project_name(name), do: name

  # Returns a MapSet of file_paths for the first non-imported occurrence of each team_name.
  # Used to render the "Import Team" button only once per team.
  defp first_team_occurrences(transcripts) do
    transcripts
    |> Enum.filter(fn t ->
      t.is_team_session and is_binary(t[:team_name]) and not t.already_imported
    end)
    |> Enum.uniq_by(& &1[:team_name])
    |> Enum.map(& &1.file_path)
    |> MapSet.new()
  end

  defp non_empty(nil), do: nil
  defp non_empty(""), do: nil

  defp non_empty(str) when is_binary(str) do
    case String.trim(str) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp truncate_text(nil), do: nil

  defp truncate_text(text) do
    normalized = text |> String.replace(~r/\s+/, " ") |> String.trim()

    case normalized do
      "" -> nil
      s when byte_size(s) <= @max_label_length -> s
      s -> String.slice(s, 0, @max_label_length - 1) <> "\u2026"
    end
  end

  defp short_id(nil), do: "????????"
  defp short_id(id), do: String.slice(to_string(id), 0, 8)

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
