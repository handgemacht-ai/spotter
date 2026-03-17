defmodule SpotterWeb.PlansLive do
  @moduledoc "LiveView for browsing project epics. Uses sidebar project selector via ProjectContext."
  use Phoenix.LiveView

  import SpotterWeb.PlanComponents

  alias Spotter.Beads.BeadQueries
  alias Spotter.Plans

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       epics: [],
       grouped_epics: [],
       orphan_beads: [],
       project_name: nil,
       loading: false
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      if connected?(socket) do
        project_name =
          case normalize_param(params["project"]) do
            nil -> nil
            raw -> resolve_project_name(socket.assigns, raw)
          end

        socket
        |> assign(
          project_name: project_name,
          loading: true,
          epics: [],
          grouped_epics: [],
          orphan_beads: []
        )
        |> start_async(:plans, fn -> do_load(project_name) end)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async(:plans, {:ok, {:project, epics, orphans}}, socket) do
    {:noreply, assign(socket, epics: epics, orphan_beads: orphans, loading: false)}
  end

  def handle_async(:plans, {:ok, {:grouped, grouped}}, socket) do
    {:noreply, assign(socket, grouped_epics: grouped, loading: false)}
  end

  def handle_async(:plans, {:exit, _reason}, socket) do
    {:noreply, assign(socket, loading: false)}
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

  defp do_load(nil), do: {:grouped, load_grouped_epics()}

  defp do_load(project) do
    case Plans.list_plans(project) do
      {:ok, epics} ->
        orphans =
          case BeadQueries.list_orphan_issues(project, :open) do
            {:ok, result} -> result
            _ -> []
          end

        {:project, epics, orphans}

      _ ->
        {:project, [], []}
    end
  end

  defp load_grouped_epics do
    case Plans.list_projects() do
      {:ok, projects} ->
        projects
        |> Task.async_stream(&fetch_project_epics/1,
          max_concurrency: 4,
          timeout: 5_000,
          on_timeout: :kill_task
        )
        |> Enum.flat_map(fn
          {:ok, {name, epics}} when epics != [] -> [{name, epics}]
          _ -> []
        end)

      _ ->
        []
    end
  end

  defp fetch_project_epics(%{project: name}) do
    case Plans.list_plans(name) do
      {:ok, epics} -> {name, epics}
      _ -> {name, []}
    end
  end

  defp grouped_plans(assigns) do
    ~H"""
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
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container" data-testid="plans-root">
      <div class="page-header">
        <h1>Plans</h1>
      </div>

      <%= if @project_name do %>
        <%= if @loading do %>
          <div class="loading-state" data-testid="plans-loading">Loading plans…</div>
        <% else %>
          <.epic_table epics={@epics} project={@project_name} />
          <div :if={@epics == [] and @orphan_beads == []} class="empty-state">
            No plans found for this project.
          </div>
          <%= if @orphan_beads != [] do %>
            <h2 class="text-lg font-semibold mb-2 mt-6">Standalone Beads</h2>
            <.epic_table epics={@orphan_beads} project={@project_name} />
          <% end %>
        <% end %>
      <% else %>
        <%= if @loading do %>
          <div class="loading-state" data-testid="plans-loading">Loading plans…</div>
        <% else %>
          <.grouped_plans grouped_epics={@grouped_epics} />
        <% end %>
      <% end %>
    </div>
    """
  end
end
