defmodule SpotterWeb.PlansLive do
  @moduledoc "LiveView for browsing project plans with search, filter, and sort."
  use Phoenix.LiveView

  import SpotterWeb.PlanComponents

  alias Spotter.Beads.BeadQueries

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       epics: [],
       orphan_beads: [],
       project_name: nil,
       search: "",
       hide_closed: true,
       sort: :priority,
       dir: :asc,
       error: nil,
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

        search = params["q"] || ""
        hide_closed = params["hide_closed"] != "false"
        sort = parse_sort(params["sort"])
        dir = parse_dir(params["dir"])

        socket
        |> assign(
          project_name: project_name,
          search: search,
          hide_closed: hide_closed,
          sort: sort,
          dir: dir,
          loading: project_name != nil,
          error: nil,
          epics: [],
          orphan_beads: []
        )
        |> maybe_load(project_name, search, hide_closed, sort, dir)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async(:plans, {:ok, {:ok, beads}}, socket) do
    {epics, orphans} = split_beads(beads)
    {:noreply, assign(socket, epics: epics, orphan_beads: orphans, loading: false)}
  end

  def handle_async(:plans, {:ok, {:error, error_atom}}, socket) do
    {:noreply, assign(socket, error: error_message(error_atom), loading: false)}
  end

  def handle_async(:plans, {:exit, _reason}, socket) do
    {:noreply, assign(socket, loading: false, error: "Failed to load plans.")}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, push_filter_patch(socket, search: q)}
  end

  @impl true
  def handle_event("toggle_closed", _params, socket) do
    {:noreply, push_filter_patch(socket, hide_closed: !socket.assigns.hide_closed)}
  end

  @impl true
  def handle_event("sort", %{"col" => col}, socket) do
    new_sort = parse_sort(col)

    new_dir =
      if new_sort == socket.assigns.sort,
        do: toggle_dir(socket.assigns.dir),
        else: default_dir(new_sort)

    {:noreply, push_filter_patch(socket, sort: new_sort, dir: new_dir)}
  end

  defp maybe_load(socket, nil, _search, _hide_closed, _sort, _dir), do: socket

  defp maybe_load(socket, project, search, hide_closed, sort, dir) do
    status = if hide_closed, do: :open, else: :all

    start_async(socket, :plans, fn ->
      BeadQueries.search_beads(project,
        query: search,
        status: status,
        sort: sort,
        dir: dir
      )
    end)
  end

  defp split_beads(beads) do
    Enum.split_with(beads, &(&1.issue_type == "epic"))
  end

  defp push_filter_patch(socket, overrides) do
    assigns = Map.merge(socket.assigns, Map.new(overrides))

    params =
      %{}
      |> put_if("project", assigns[:project_name])
      |> put_if("q", non_empty(assigns[:search]))
      |> Map.put("hide_closed", to_string(assigns[:hide_closed]))
      |> Map.put("sort", to_string(assigns[:sort]))
      |> Map.put("dir", to_string(assigns[:dir]))

    push_patch(socket, to: "/plans?" <> URI.encode_query(params))
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, val), do: Map.put(map, key, val)

  defp non_empty(""), do: nil
  defp non_empty(s), do: s

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

  defp parse_sort("created_at"), do: :created_at
  defp parse_sort(_), do: :priority

  defp parse_dir("asc"), do: :asc
  defp parse_dir(_), do: :desc

  defp toggle_dir(:asc), do: :desc
  defp toggle_dir(:desc), do: :asc

  defp default_dir(:created_at), do: :desc
  defp default_dir(_), do: :asc

  defp error_message(:connection_refused), do: "Dolt is not running. Start it with `just up`."
  defp error_message(:unknown_project), do: "Project not found in Dolt."
  defp error_message(:query_timeout), do: "Query timed out. Try a more specific search."
  defp error_message(_), do: "Failed to load plans."

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container" data-testid="plans-root">
      <div class="page-header">
        <h1>Plans</h1>
      </div>

      <%= if @error do %>
        <div class="empty-state" data-testid="plans-error">{@error}</div>
      <% else %>
        <%= if @project_name do %>
          <.filter_bar search={@search} hide_closed={@hide_closed} />

          <%= if @loading do %>
            <div class="loading-state" data-testid="plans-loading">Loading plans…</div>
          <% else %>
            <.epic_table epics={@epics} project={@project_name} sort={@sort} dir={@dir} />

            <%= if @orphan_beads != [] do %>
              <h2 class="plans-section-heading">Standalone Beads</h2>
              <.epic_table
                epics={@orphan_beads}
                project={@project_name}
                sort={@sort}
                dir={@dir}
              />
            <% end %>

            <div
              :if={@epics == [] and @orphan_beads == []}
              class="empty-state"
              data-testid="plans-empty"
            >
              <%= if @search != "" do %>
                No plans match your search.
              <% else %>
                No plans found for this project.
              <% end %>
            </div>
          <% end %>
        <% else %>
          <div class="empty-state" data-testid="select-project-prompt">
            Select a project from the sidebar.
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end
end
