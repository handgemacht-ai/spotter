defmodule SpotterWeb.PlansLive do
  @moduledoc "LiveView for browsing project epics. Uses sidebar project selector via ProjectContext."
  use Phoenix.LiveView

  import SpotterWeb.PlanComponents

  alias Spotter.Plans

  @query_timeout 500

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
        # Only filter to a single project when an explicit ?project= param is present.
        # Without it, show the grouped-by-project view with all projects.
        project_name =
          case normalize_param(params["project"]) do
            nil -> nil
            raw -> resolve_project_name(socket.assigns, raw)
          end

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

  # Resolve a ?project= param to a project name.
  # If it matches a project ID from the sidebar, return that project's name.
  # Otherwise, treat it as a literal project name (for direct URL usage).
  defp resolve_project_name(%{projects: projects}, raw) when is_list(projects) do
    case Enum.find(projects, &(&1.id == raw)) do
      %{name: name} -> name
      _ -> raw
    end
  end

  defp resolve_project_name(_, raw), do: raw

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
      projects
      |> Task.async_stream(
        fn %{project: name} ->
          case Plans.list_plans(name) do
            {:ok, epics} -> {name, epics}
            _ -> {name, []}
          end
        end,
        max_concurrency: 4,
        timeout: @query_timeout,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, {name, epics}} when epics != [] -> [{name, epics}]
        _ -> []
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
        <.epic_table epics={@epics} project={@project_name} />
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
            <.epic_table epics={epics} project={project} />
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
