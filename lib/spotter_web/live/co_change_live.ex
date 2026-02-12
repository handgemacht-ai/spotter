defmodule SpotterWeb.CoChangeLive do
  use Phoenix.LiveView

  alias Spotter.Transcripts.{CoChangeGroup, Project}

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    projects =
      try do
        Project |> Ash.read!()
      rescue
        _ -> []
      end

    {:ok,
     socket
     |> assign(
       projects: projects,
       selected_project_id: nil,
       scope: :file,
       rows: []
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = parse_project_id(params["project_id"])

    socket =
      socket
      |> assign(selected_project_id: project_id)
      |> load_rows()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = parse_project_id(raw_id)
    path = if project_id, do: "/co-change?project_id=#{project_id}", else: "/co-change"

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("toggle_scope", %{"scope" => scope}, socket) do
    scope = parse_scope(scope)

    {:noreply,
     socket
     |> assign(scope: scope)
     |> load_rows()}
  end

  defp parse_project_id("all"), do: nil
  defp parse_project_id(nil), do: nil
  defp parse_project_id(""), do: nil
  defp parse_project_id(id), do: id

  defp parse_scope("directory"), do: :directory
  defp parse_scope(_), do: :file

  defp load_rows(%{assigns: %{selected_project_id: nil}} = socket) do
    assign(socket, rows: [])
  end

  defp load_rows(socket) do
    %{selected_project_id: project_id, scope: scope} = socket.assigns

    groups =
      try do
        CoChangeGroup
        |> Ash.Query.filter(project_id == ^project_id and scope == ^scope)
        |> Ash.read!()
      rescue
        _ -> []
      end

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

  defp selected_project(assigns) do
    Enum.find(assigns.projects, &(&1.id == assigns.selected_project_id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <div class="page-header">
        <h1>Co-change Groups</h1>
        <div>
          <a :if={@selected_project_id} href={"/projects/#{@selected_project_id}/heatmap"} class="btn btn-ghost">Heatmap</a>
          <a :if={@selected_project_id} href={"/hotspots?project_id=#{@selected_project_id}"} class="btn btn-ghost">Hotspots</a>
        </div>
      </div>

      <div class="filter-section">
        <div>
          <label class="filter-label">Project</label>
          <div class="filter-bar">
            <button
              phx-click="filter_project"
              phx-value-project-id="all"
              class={"filter-btn#{if @selected_project_id == nil, do: " is-active"}"}
            >
              All
            </button>
            <button
              :for={project <- @projects}
              phx-click="filter_project"
              phx-value-project-id={project.id}
              class={"filter-btn#{if @selected_project_id == project.id, do: " is-active"}"}
            >
              {project.name}
            </button>
          </div>
        </div>

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

      <%= if @selected_project_id == nil do %>
        <div class="empty-state">
          Select a project to view co-change groups.
        </div>
      <% else %>
        <%= if @rows == [] do %>
          <div class="empty-state">
            <%= if selected_project(assigns) do %>
              No co-change groups for {selected_project(assigns).name} yet.
            <% else %>
              Project not found.
            <% end %>
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
