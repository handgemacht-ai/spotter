defmodule SpotterWeb.PlansLive do
  use Phoenix.LiveView

  import SpotterWeb.PlanComponents

  alias Spotter.Beads.BeadQueries

  @query_timeout 2_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       project_summaries: [],
       selected_project: nil,
       epics: [],
       epic_detail: nil,
       dolt_available: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project = params["project"]
    epic_id = params["epic_id"]

    socket =
      if connected?(socket) do
        socket
        |> ensure_dolt_probed()
        |> assign(selected_project: project)
        |> load_epics(project)
        |> maybe_load_epic_detail(project, epic_id)
      else
        assign(socket, selected_project: project, epic_detail: nil)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_project", %{"project" => project}, socket) do
    current = socket.assigns.selected_project

    if project == current do
      {:noreply, push_patch(socket, to: "/plans")}
    else
      {:noreply, push_patch(socket, to: "/plans?project=#{URI.encode(project)}")}
    end
  end

  defp ensure_dolt_probed(%{assigns: %{dolt_available: nil}} = socket) do
    summaries = safe_query(fn -> BeadQueries.project_summaries() end, :error)

    case summaries do
      :error ->
        assign(socket, dolt_available: false, project_summaries: [])

      result ->
        assign(socket, dolt_available: true, project_summaries: result)
    end
  end

  defp ensure_dolt_probed(socket), do: socket

  defp load_epics(%{assigns: %{dolt_available: false}} = socket, _project),
    do: assign(socket, epics: [])

  defp load_epics(socket, nil), do: assign(socket, epics: [])

  defp load_epics(socket, project) do
    epics = safe_query(fn -> BeadQueries.list_epics(project) end, [])
    assign(socket, epics: epics)
  end

  defp maybe_load_epic_detail(%{assigns: %{dolt_available: false}} = socket, _project, _epic_id),
    do: assign(socket, epic_detail: nil)

  defp maybe_load_epic_detail(socket, _project, nil), do: assign(socket, epic_detail: nil)

  defp maybe_load_epic_detail(socket, project, epic_id) do
    detail = safe_query(fn -> BeadQueries.get_epic(project, epic_id) end, nil)
    assign(socket, epic_detail: detail)
  end

  defp safe_query(fun, default) do
    task = Task.async(fun)

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

      <div class="filter-section" data-project={@selected_project || ""}>
        <div>
          <label class="filter-label">Projects</label>
          <div class="filter-bar">
            <%= for summary <- @project_summaries do %>
              <.project_chip
                project={summary.project}
                epic_count={summary.epic_count}
                active={@selected_project == summary.project}
              />
            <% end %>
          </div>
        </div>
      </div>

      <%= if @epic_detail do %>
        <div class="plan-epic-detail" data-testid="epic-detail">
          <div class="plan-epic-detail-header">
            <h2>{@epic_detail.title}</h2>
            <div class="flex gap-2">
              <.status_badge status={@epic_detail.status} />
              <.priority_badge priority={@epic_detail.priority} />
            </div>
          </div>
          <p :if={@epic_detail.description} class="plan-epic-description">
            {@epic_detail.description}
          </p>
        </div>
      <% else %>
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
              <.epic_table_row epic={epic} project={@selected_project} />
            <% end %>
          </tbody>
        </table>
        <div :if={@epics == [] && @selected_project} class="empty-state">
          No epics found for this project.
        </div>
        <div :if={@epics == [] && is_nil(@selected_project)} class="empty-state">
          Select a project to view its epics.
        </div>
      <% end %>
    </div>
    """
  end
end
