defmodule SpotterWeb.RetrosLive do
  use Phoenix.LiveView

  alias Spotter.Transcripts.{Project, RetroItem, RetroSubmission}
  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  @impl true
  def mount(_params, _session, socket) do
    project_counts = list_project_submission_counts()

    {:ok,
     socket
     |> assign(
       project_counts: project_counts,
       selected_project_id: first_project_id(project_counts),
       submissions: [],
       expanded_ids: MapSet.new()
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

  @impl true
  def handle_event("toggle_submission", %{"id" => id}, socket) do
    expanded_ids = socket.assigns.expanded_ids

    expanded_ids =
      if MapSet.member?(expanded_ids, id),
        do: MapSet.delete(expanded_ids, id),
        else: MapSet.put(expanded_ids, id)

    {:noreply, assign(socket, expanded_ids: expanded_ids)}
  end

  @impl true
  def handle_event("rate_item", %{"item-id" => item_id, "rating" => rating}, socket) do
    Tracer.with_span "spotter.retros_live.rate_item" do
      rating_atom = String.to_existing_atom(rating)
      Tracer.set_attribute(:"retro.item_id", item_id)
      Tracer.set_attribute(:"retro.rating", rating)

      item = Ash.get!(RetroItem, item_id)
      Ash.update!(item, %{rating: rating_atom}, action: :rate)
    end

    {:noreply, load_submissions(socket)}
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

  defp rating_distribution(items) do
    items
    |> Enum.frequencies_by(& &1.rating)
    |> Enum.reject(fn {rating, _} -> rating == :undecided end)
    |> Enum.sort_by(fn {rating, _} -> rating_sort_key(rating) end)
  end

  defp rating_sort_key(:useful), do: 0
  defp rating_sort_key(:not_useful), do: 1
  defp rating_sort_key(_), do: 2

  defp rating_label(:useful), do: "useful"
  defp rating_label(:not_useful), do: "not useful"
  defp rating_label(other), do: to_string(other)

  defp category_distribution(items) do
    items
    |> Enum.frequencies_by(& &1.category)
    |> Enum.sort_by(fn {_cat, count} -> -count end)
  end

  defp category_label(:knowledge_gained), do: "Knowledge gained"
  defp category_label(:effective_strategy), do: "Effective strategy"
  defp category_label(:gotcha), do: "Gotcha"
  defp category_label(:requirements_clarity), do: "Requirements clarity"
  defp category_label(:struggle), do: "Struggle"
  defp category_label(other), do: to_string(other)

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
        phx-click="toggle_submission"
        phx-value-id={sub.id}
        style="cursor: pointer;"
      >
        <div class="flex items-center gap-2 mb-2">
          <span class="text-xs">{if MapSet.member?(@expanded_ids, sub.id), do: "▾", else: "▸"}</span>
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
          <span
            :for={{category, count} <- category_distribution(sub.items)}
            class={"retro-category-badge retro-category-#{category}"}
          >
            {category} ({count})
          </span>
          <span
            :for={{rating, count} <- rating_distribution(sub.items)}
            class={"text-xs rating-summary rating-#{rating}"}
          >
            {count} {rating_label(rating)}
          </span>
        </div>
        <div :if={MapSet.member?(@expanded_ids, sub.id)} style="margin-top: 0.5rem;">
          <div :for={item <- sub.items} class="retro-item">
            <span class={"retro-category-badge retro-category-#{item.category}"}>
              {category_label(item.category)}
            </span>
            <p class="text-sm">{item.observation}</p>
            <p class="text-muted text-xs">{item.explanation}</p>
            <div class="flex items-center gap-2" style="margin-top: 0.25rem;">
              <button
                :for={rating <- ~w(useful undecided not_useful)a}
                phx-click="rate_item"
                phx-value-item-id={item.id}
                phx-value-rating={rating}
                class={"rating-btn#{if item.rating == rating, do: " is-active"} rating-#{rating}"}
              >
                {rating}
              </button>
            </div>
          </div>
        </div>
      </div>

      <div :if={!@selected_project_id} class="empty-state">
        No project selected.
      </div>
    </div>
    """
  end
end
