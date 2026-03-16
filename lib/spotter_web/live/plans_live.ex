defmodule SpotterWeb.PlansLive do
  @moduledoc "LiveView for browsing project epics. Uses sidebar project selector via ProjectContext."
  use Phoenix.LiveView

  import SpotterWeb.PlanComponents

  alias Spotter.Plans

  @query_timeout 2_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       epics: [],
       grouped_epics: [],
       project_name: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      if connected?(socket) do
        project_name =
          resolve_project_name(socket.assigns) || normalize_param(params["project"])

        socket = assign(socket, project_name: project_name)

        if project_name do
          load_filtered_epics(socket, project_name)
        else
          load_grouped_epics(socket)
        end
      else
        socket
      end

    {:noreply, socket}
  end

  defp resolve_project_name(%{current_project_id: nil}), do: nil

  defp resolve_project_name(%{current_project_id: project_id, projects: projects}) do
    case Enum.find(projects, &(&1.id == project_id)) do
      %{name: name} -> name
      _ -> nil
    end
  end

  defp resolve_project_name(_), do: nil

  defp normalize_param(nil), do: nil
  defp normalize_param(""), do: nil
  defp normalize_param(val), do: val

  defp load_filtered_epics(socket, project_name) do
    epics = safe_query(fn -> Plans.list_plans(project_name) end, [])
    assign(socket, epics: epics, grouped_epics: [])
  end

  defp load_grouped_epics(socket) do
    projects = safe_query(fn -> Plans.list_projects() end, [])

    grouped =
      Enum.flat_map(projects, fn %{project: name} ->
        epics = safe_query(fn -> Plans.list_plans(name) end, [])
        if epics == [], do: [], else: [{name, epics}]
      end)

    assign(socket, epics: [], grouped_epics: grouped)
  end

  defp safe_query(fun, default) do
    task =
      Task.async(fn ->
        try do
          fun.()
        rescue
          _ -> {:error, :exception}
        end
      end)

    case Task.yield(task, @query_timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} -> result
      _ -> default
    end
  catch
    _, _ -> default
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container" data-testid="plans-root">
      <div class="page-header">
        <h1>Plans</h1>
      </div>

      <%= if @project_name do %>
        <table class="epic-table" data-testid="epic-table">
          <thead>
            <tr>
              <th>ID</th>
              <th>Title</th>
              <th>Status</th>
              <th>Priority</th>
              <th>Tasks</th>
              <th>Created</th>
            </tr>
          </thead>
          <tbody>
            <%= for epic <- @epics do %>
              <.epic_table_row epic={epic} project={@project_name} />
            <% end %>
          </tbody>
        </table>
        <div :if={@epics == []} class="empty-state">
          No epics found for this project.
        </div>
      <% else %>
        <%= if @grouped_epics != [] do %>
          <%= for {project, epics} <- @grouped_epics do %>
            <h2
              class="text-lg font-semibold mb-2 mt-6"
              data-testid="project-group-header"
              data-project={project}
            >
              {project}
            </h2>
            <table class="epic-table" data-testid="epic-table">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Title</th>
                  <th>Status</th>
                  <th>Priority</th>
                  <th>Tasks</th>
                  <th>Created</th>
                </tr>
              </thead>
              <tbody>
                <%= for epic <- epics do %>
                  <.epic_table_row epic={epic} project={project} />
                <% end %>
              </tbody>
            </table>
          <% end %>
        <% else %>
          <div class="empty-state">
            No plans available. Select a project or ensure Dolt is running.
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
