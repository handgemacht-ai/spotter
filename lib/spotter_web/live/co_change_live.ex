defmodule SpotterWeb.CoChangeLive do
  use Phoenix.LiveView

  alias Spotter.Transcripts.{CoChangeGroup, Project}

  require Ash.Query

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    case Ash.get(Project, project_id) do
      {:ok, project} ->
        {:ok,
         socket
         |> assign(project: project, scope: :file)
         |> load_rows()}

      _ ->
        {:ok, assign(socket, project: nil, rows: [])}
    end
  end

  @impl true
  def handle_event("toggle_scope", %{"scope" => scope}, socket) do
    scope = parse_scope(scope)

    {:noreply,
     socket
     |> assign(scope: scope)
     |> load_rows()}
  end

  defp parse_scope("directory"), do: :directory
  defp parse_scope(_), do: :file

  defp load_rows(socket) do
    %{project: project, scope: scope} = socket.assigns

    groups =
      CoChangeGroup
      |> Ash.Query.filter(project_id == ^project.id and scope == ^scope)
      |> Ash.read!()

    rows = derive_rows(groups)
    assign(socket, rows: rows)
  end

  defp derive_rows(groups) do
    groups
    |> Enum.flat_map(fn group ->
      Enum.map(group.members, fn member ->
        {member, group}
      end)
    end)
    |> Enum.group_by(fn {member, _} -> member end, fn {_, group} -> group end)
    |> Enum.map(fn {member, member_groups} ->
      max_freq = member_groups |> Enum.map(& &1.frequency_30d) |> Enum.max()

      sorted_groups =
        Enum.sort_by(member_groups, fn g -> {-g.frequency_30d, g.group_key} end)

      %{member: member, max_frequency_30d: max_freq, groups: sorted_groups}
    end)
    |> Enum.sort_by(fn r -> {-r.max_frequency_30d, r.member} end)
  end

  defp format_group(group) do
    members = Enum.join(group.members, " + ")
    "#{members} \u00d7#{group.frequency_30d}"
  end

  defp scope_label(:file), do: "File"
  defp scope_label(:directory), do: "Directory"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <%= if @project == nil do %>
        <div class="empty-state">
          <p>Project not found.</p>
          <a href="/" class="btn">Back to dashboard</a>
        </div>
      <% else %>
        <div class="page-header">
          <h1>Co-change Groups &mdash; {@project.name}</h1>
          <a href="/" class="btn btn-ghost">Back</a>
        </div>

        <div class="filter-section">
          <div>
            <label class="filter-label">Scope</label>
            <div class="filter-bar">
              <button
                phx-click="toggle_scope"
                phx-value-scope="file"
                class={"filter-btn#{if @scope == :file, do: " is-active"}"}
              >
                Files
              </button>
              <button
                phx-click="toggle_scope"
                phx-value-scope="directory"
                class={"filter-btn#{if @scope == :directory, do: " is-active"}"}
              >
                Directories
              </button>
            </div>
          </div>
        </div>

        <%= if @rows == [] do %>
          <div class="empty-state">
            No co-change groups for this project yet.
          </div>
        <% else %>
          <table>
            <thead>
              <tr>
                <th>{scope_label(@scope)}</th>
                <th>Max Co-Change (30d)</th>
                <th>Co-change groups</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @rows}>
                <td title={row.member}>{row.member}</td>
                <td>{row.max_frequency_30d}</td>
                <td>
                  <span :for={group <- row.groups} class="badge" style="margin-right: 0.5rem;">
                    {format_group(group)}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        <% end %>
      <% end %>
    </div>
    """
  end
end
