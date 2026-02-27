defmodule SpotterWeb.RetrosLive do
  use Phoenix.LiveView

  alias Spotter.Transcripts.{Project, RetroSubmission}
  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    project_counts = list_project_submission_counts()

    {:ok,
     socket
     |> assign(
       project_counts: project_counts,
       selected_project_id: first_project_id(project_counts),
       submissions: []
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id =
      normalize_project_id(socket.assigns.project_counts, parse_project_id(params["project_id"]))

    socket =
      socket
      |> assign(selected_project_id: project_id)
      |> load_submissions()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_project", %{"project-id" => raw_id}, socket) do
    project_id = normalize_project_id(socket.assigns.project_counts, parse_project_id(raw_id))
    path = if project_id, do: "/retros?project_id=#{project_id}", else: "/retros"

    {:noreply, push_patch(socket, to: path)}
  end

  defp parse_project_id(id) when is_binary(id) and id != "" and id != "all", do: id
  defp parse_project_id(_), do: nil

  defp first_project_id([%{project_id: id} | _]), do: id
  defp first_project_id(_), do: nil

  defp normalize_project_id(project_counts, project_id) do
    first = first_project_id(project_counts)

    case project_id do
      nil -> first
      _ -> if project_exists?(project_counts, project_id), do: project_id, else: first
    end
  end

  defp project_exists?(project_counts, project_id) do
    Enum.any?(project_counts, &(&1.project_id == project_id))
  end

  defp list_project_submission_counts do
    projects = Project |> Ash.Query.sort(name: :asc) |> Ash.read!()

    counts_by_project =
      RetroSubmission
      |> Ash.Query.select([:project_id])
      |> Ash.read!()
      |> Enum.frequencies_by(& &1.project_id)

    Enum.map(projects, fn project ->
      %{
        project_id: project.id,
        project_name: project.name,
        submission_count: Map.get(counts_by_project, project.id, 0)
      }
    end)
  end

  defp load_submissions(%{assigns: %{selected_project_id: nil}} = socket) do
    assign(socket, submissions: [])
  end

  defp load_submissions(%{assigns: %{selected_project_id: project_id}} = socket) do
    submissions =
      RetroSubmission
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.Query.sort(submitted_at: :desc)
      |> Ash.Query.load([:items, :session])
      |> Ash.read!()

    assign(socket, submissions: submissions)
  end

  defp session_label(session) do
    session.slug || String.slice(session.session_id, 0, 8)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container" data-testid="retros-root">
      <div class="page-header">
        <h1>Retros</h1>
      </div>

      <div :if={Phoenix.Flash.get(@flash, :info)} class="flash-info">
        {Phoenix.Flash.get(@flash, :info)}
      </div>

      <div :if={Phoenix.Flash.get(@flash, :error)} class="flash-error">
        {Phoenix.Flash.get(@flash, :error)}
      </div>

      <div class="filter-section">
        <div>
          <label class="filter-label">Project</label>
          <div class="filter-bar">
            <button
              :for={pc <- @project_counts}
              phx-click="filter_project"
              phx-value-project-id={pc.project_id}
              class={"filter-btn#{if @selected_project_id == pc.project_id, do: " is-active"}"}
            >
              {pc.project_name} ({pc.submission_count})
            </button>
          </div>
        </div>
      </div>

      <div :if={@selected_project_id && @submissions == []} class="empty-state">
        No retro submissions for the selected project.
      </div>

      <div
        :for={sub <- @submissions}
        :if={@selected_project_id}
        class="annotation-card"
      >
        <div class="flex items-center gap-2 mb-2">
          <span class="text-sm"><strong>{sub.summary}</strong></span>
          <span :if={sub.session} class="text-muted text-xs">
            {session_label(sub.session)}
          </span>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-muted text-xs">
            {Calendar.strftime(sub.submitted_at, "%Y-%m-%d %H:%M")}
          </span>
          <span class="badge">
            {length(sub.items)} items
          </span>
        </div>
      </div>

      <div :if={!@selected_project_id} class="empty-state">
        No project selected.
      </div>
    </div>
    """
  end
end
