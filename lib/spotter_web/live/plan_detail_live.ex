defmodule SpotterWeb.PlanDetailLive do
  @moduledoc "LiveView for displaying a single epic's detail with parsed sections, mermaid diagrams, and child tasks."
  use Phoenix.LiveView

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  import SpotterWeb.PlanComponents

  alias Spotter.Beads.BeadContentParser
  alias Spotter.Beads.BeadQueries
  alias Spotter.Beads.BeadStructs

  @query_timeout 2_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       project: nil,
       epic: nil,
       children: [],
       parsed_content: nil,
       dolt_available: nil,
       expanded_tasks: MapSet.new(),
       selection: nil
     )}
  end

  @impl true
  def handle_params(%{"project" => project, "epic_id" => epic_id}, _uri, socket) do
    socket =
      if connected?(socket) do
        socket
        |> assign(project: project)
        |> load_detail(project, epic_id)
      else
        assign(socket, project: project)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_task", %{"task_id" => task_id}, socket) do
    expanded = socket.assigns.expanded_tasks

    expanded =
      if MapSet.member?(expanded, task_id),
        do: MapSet.delete(expanded, task_id),
        else: MapSet.put(expanded, task_id)

    {:noreply, assign(socket, expanded_tasks: expanded)}
  end

  @impl true
  def handle_event("plan_text_selected", %{"selected_text" => text} = params, socket) do
    %{epic: epic, project: project} = socket.assigns

    selection = %{text: text, section: params["section"]}
    socket = assign(socket, selection: selection)

    maybe_create_annotation(epic, project, text, params["comment"])

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_annotation", %{"comment" => comment}, socket) do
    %{epic: epic, project: project, selection: selection} = socket.assigns

    if selection do
      maybe_create_annotation(epic, project, selection.text, comment)
    end

    {:noreply, assign(socket, selection: nil)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selection: nil)}
  end

  defp maybe_create_annotation(nil, _project, _text, _comment), do: :skip
  defp maybe_create_annotation(_epic, _project, _text, nil), do: :skip
  defp maybe_create_annotation(_epic, _project, _text, ""), do: :skip

  defp maybe_create_annotation(epic, project, text, comment) do
    Tracer.with_span "spotter.plan_detail.create_annotation" do
      Tracer.set_attribute("spotter.beads.project", project)
      Tracer.set_attribute("spotter.beads.bead_id", epic.id)
      Tracer.set_attribute("spotter.plan_detail.text_length", String.length(text))

      project_id = lookup_project_id(project)

      case Spotter.Transcripts.Annotation
           |> Ash.Changeset.for_create(:create, %{
             source: :plan,
             bead_id: epic.id,
             selected_text: text,
             comment: comment,
             purpose: :review,
             project_id: project_id
           })
           |> Ash.create() do
        {:ok, _annotation} ->
          :ok

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          :error
      end
    end
  end

  defp lookup_project_id(project_name) do
    case Spotter.Transcripts.Project
         |> Ash.Query.filter(name == ^project_name)
         |> Ash.read_one() do
      {:ok, %{id: id}} -> id
      _ -> nil
    end
  end

  defp load_detail(socket, project, epic_id) do
    Tracer.with_span "spotter.plan_detail.load" do
      Tracer.set_attribute("spotter.beads.project", project)
      Tracer.set_attribute("spotter.beads.epic_id", epic_id)

      {epic, children} = fetch_data(project, epic_id)

      parsed =
        if epic do
          %{
            sections: BeadContentParser.extract_sections_ordered(epic.description),
            mermaid_blocks: BeadContentParser.extract_mermaid_blocks(epic.description),
            acceptance_rows: BeadContentParser.extract_acceptance_table(epic.description)
          }
        end

      dolt_available = epic != nil

      Tracer.set_attribute("spotter.plan_detail.dolt_available", dolt_available)

      if children != [] do
        Tracer.set_attribute("spotter.plan_detail.child_count", length(children))
      end

      assign(socket,
        epic: epic,
        children: children,
        parsed_content: parsed,
        dolt_available: dolt_available
      )
    end
  end

  defp fetch_data(project, epic_id) do
    case Application.get_env(:spotter, :plan_detail_test_data) do
      %{} = test_data ->
        key = "#{project}/#{epic_id}"

        case Map.get(test_data, key) do
          %{epic: epic_map, children: children_maps} ->
            {BeadStructs.Epic.from_row(epic_map), BeadStructs.Task.from_rows(children_maps)}

          _ ->
            fetch_from_dolt(project, epic_id)
        end

      _ ->
        fetch_from_dolt(project, epic_id)
    end
  end

  defp fetch_from_dolt(project, epic_id) do
    epic = safe_query(fn -> BeadQueries.get_epic(project, epic_id) end, nil)
    children = safe_query(fn -> BeadQueries.list_children(project, epic_id) end, [])
    {epic, children}
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
    <div class="container" data-testid="plan-detail-root">
      <div class="page-header">
        <.link
          patch={back_path(@project)}
          class="plan-back-link"
          data-testid="back-to-plans"
        >
          &larr; Back to Plans
        </.link>
      </div>

      <%= if @epic do %>
        <div class="plan-epic-detail" data-testid="epic-detail">
          <div class="plan-epic-detail-header" data-testid="epic-detail-header">
            <h2>{@epic.title}</h2>
            <div class="flex gap-2">
              <.status_badge status={@epic.status} />
              <.priority_badge priority={@epic.priority} />
            </div>
          </div>

          <%= if @parsed_content do %>
            <div
              data-testid="epic-sections"
              id="plan-sections"
              phx-hook="PlanHighlighter"
            >
              <%= for {heading, body} <- @parsed_content.sections do %>
                <div class="plan-section" data-plan-section={heading}>
                  <h3 class="plan-section-heading" data-testid="section-heading">{heading}</h3>
                  <div class="plan-section-body">
                    <p :for={line <- String.split(body, "\n", trim: true)}>{line}</p>
                  </div>
                </div>
              <% end %>

              <%= for {block, idx} <- Enum.with_index(@parsed_content.mermaid_blocks) do %>
                <div
                  class="plan-mermaid-block"
                  id={"mermaid-block-#{idx}"}
                  phx-hook="MermaidHook"
                  data-mermaid-source={block}
                  data-testid="mermaid-block"
                >
                  <pre class="mermaid-fallback"><code>{block}</code></pre>
                </div>
              <% end %>

              <.acceptance_table
                :if={@parsed_content.acceptance_rows != []}
                rows={@parsed_content.acceptance_rows}
              />
            </div>

            <%= if @selection do %>
              <div class="plan-annotation-form" data-testid="selection-active">
                <p class="plan-annotation-selected-text">
                  &ldquo;{String.slice(@selection.text, 0, 200)}&rdquo;
                </p>
                <form phx-submit="save_annotation">
                  <textarea
                    name="comment"
                    placeholder="Add your annotation..."
                    rows="3"
                    class="plan-annotation-textarea"
                  ></textarea>
                  <div class="plan-annotation-actions">
                    <button type="submit" class="btn btn-primary">Save Annotation</button>
                    <button type="button" phx-click="clear_selection" class="btn btn-secondary">
                      Cancel
                    </button>
                  </div>
                </form>
              </div>
            <% end %>
          <% end %>

          <%= if @children != [] do %>
            <div class="plan-children" data-testid="child-tasks">
              <h3>Tasks ({length(@children)})</h3>
              <div class="plan-task-list">
                <%= for task <- @children do %>
                  <.task_row
                    task={task}
                    expanded={MapSet.member?(@expanded_tasks, task.id)}
                  />
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% else %>
        <div class="empty-state" data-testid="plan-not-found">
          {empty_message(@dolt_available)}
        </div>
      <% end %>
    </div>
    """
  end

  defp empty_message(false), do: "Plan data is currently unavailable."
  defp empty_message(_), do: "Epic not found."

  defp back_path(nil), do: "/plans"
  defp back_path(project), do: "/plans?project=#{URI.encode_www_form(project)}"
end
