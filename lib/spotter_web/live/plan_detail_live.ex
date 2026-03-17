defmodule SpotterWeb.PlanDetailLive do
  @moduledoc "LiveView for displaying a single bead's detail with parsed sections, mermaid diagrams, dependencies, annotations, and child tasks."
  use Phoenix.LiveView

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  import SpotterWeb.PlanComponents

  alias Spotter.Beads.BeadContentParser
  alias Spotter.Beads.BeadStructs
  alias Spotter.Plans

  @query_timeout 5_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       project: nil,
       bead: nil,
       children: [],
       dependencies: [],
       annotations: [],
       parsed_content: nil,
       dolt_available: nil,
       selection: nil
     )}
  end

  @impl true
  def handle_params(%{"project" => project, "bead_id" => bead_id}, _uri, socket) do
    socket =
      if connected?(socket) do
        socket
        |> assign(project: project)
        |> load_detail(project, bead_id)
      else
        assign(socket, project: project)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("plan_text_selected", %{"selected_text" => text} = params, socket) do
    %{bead: bead, project: project} = socket.assigns

    selection = %{text: text, section: params["section"]}
    socket = assign(socket, selection: selection)

    maybe_create_annotation(bead, project, text, params["comment"])

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_annotation", %{"comment" => comment}, socket) do
    %{bead: bead, project: project, selection: selection} = socket.assigns

    if selection do
      maybe_create_annotation(bead, project, selection.text, comment)
    end

    {:noreply, assign(socket, selection: nil)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selection: nil)}
  end

  defp maybe_create_annotation(nil, _project, _text, _comment), do: :skip
  defp maybe_create_annotation(_bead, _project, _text, nil), do: :skip
  defp maybe_create_annotation(_bead, _project, _text, ""), do: :skip

  defp maybe_create_annotation(bead, project, text, comment) do
    Tracer.with_span "spotter.plan_detail.create_annotation" do
      Tracer.set_attribute("spotter.beads.project", project)
      Tracer.set_attribute("spotter.beads.bead_id", bead.id)
      Tracer.set_attribute("spotter.plan_detail.text_length", String.length(text))

      project_id = lookup_project_id(project)

      case Spotter.Transcripts.Annotation
           |> Ash.Changeset.for_create(:create, %{
             source: :plan,
             bead_id: bead.id,
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

  defp load_detail(socket, project, bead_id) do
    Tracer.with_span "spotter.plan_detail.load" do
      Tracer.set_attribute("spotter.beads.project", project)
      Tracer.set_attribute("spotter.beads.bead_id", bead_id)

      {bead, children, deps, annotations} = fetch_data(project, bead_id)

      parsed = parse_bead_content(bead && bead.description)

      dolt_available = bead != nil

      Tracer.set_attribute("spotter.plan_detail.dolt_available", dolt_available)
      Tracer.set_attribute("spotter.plan_detail.child_count", length(children))
      Tracer.set_attribute("spotter.plan_detail.dep_count", length(deps))
      Tracer.set_attribute("spotter.plan_detail.annotation_count", length(annotations))

      assign(socket,
        bead: bead,
        children: children,
        dependencies: deps,
        annotations: annotations,
        parsed_content: parsed,
        dolt_available: dolt_available
      )
    end
  end

  defp parse_bead_content(nil), do: nil

  defp parse_bead_content(description) do
    sections =
      description
      |> BeadContentParser.extract_sections_ordered()
      |> Enum.map(fn {heading, body} ->
        type = BeadContentParser.classify_section(heading)
        rendered = BeadContentParser.render_section_body(body)
        {heading, body, type, rendered}
      end)

    %{
      sections: sections,
      mermaid_blocks: BeadContentParser.extract_mermaid_blocks(description),
      acceptance_rows: BeadContentParser.extract_acceptance_table(description),
      classification: BeadContentParser.extract_classification(description)
    }
  end

  defp fetch_data(project, bead_id) do
    case lookup_test_fixture(project, bead_id) do
      %{epic: epic_map, children: children_maps} ->
        bead = BeadStructs.Epic.from_row(epic_map)
        children = BeadStructs.Task.from_rows(children_maps)
        deps = safe_call(fn -> Plans.list_dependencies(project, bead_id) end, [])
        annotations = fetch_annotations(bead_id)
        {bead, children, deps, annotations}

      nil ->
        fetch_from_dolt(project, bead_id)
    end
  end

  defp lookup_test_fixture(project, bead_id) do
    with %{} = test_data <- Application.get_env(:spotter, :plan_detail_test_data),
         %{} = fixture <- Map.get(test_data, "#{project}/#{bead_id}") do
      fixture
    else
      _ -> nil
    end
  end

  defp fetch_from_dolt(project, bead_id) do
    bead_task = Task.async(fn -> safe_call(fn -> Plans.get_bead(project, bead_id) end, nil) end)

    children_task =
      Task.async(fn -> safe_call(fn -> Plans.list_children(project, bead_id) end, []) end)

    deps_task =
      Task.async(fn -> safe_call(fn -> Plans.list_dependencies(project, bead_id) end, []) end)

    annotations_task =
      Task.async(fn -> safe_call(fn -> {:ok, fetch_annotations(bead_id)} end, []) end)

    bead = Task.await(bead_task, @query_timeout)
    children = Task.await(children_task, @query_timeout)
    deps = Task.await(deps_task, @query_timeout)
    annotations = Task.await(annotations_task, @query_timeout)

    {bead, children, deps, annotations}
  end

  defp fetch_annotations(bead_id) do
    case Spotter.Transcripts.Annotation
         |> Ash.Query.for_read(:list_for_bead, %{bead_id: bead_id})
         |> Ash.read() do
      {:ok, annotations} -> annotations
      _ -> []
    end
  end

  defp safe_call(fun, default) do
    case fun.() do
      {:ok, result} -> result
      _ -> default
    end
  rescue
    _ -> default
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

      <%= if @bead do %>
        <div class="plan-bead-detail" data-testid="bead-detail">
          <div class="plan-bead-detail-header" data-testid="bead-detail-header">
            <h2>{@bead.title}</h2>
            <div class="flex gap-2">
              <.status_badge status={@bead.status} />
              <.priority_badge priority={@bead.priority} />
            </div>
          </div>

          <%= if @parsed_content do %>
            <div
              data-testid="bead-sections"
              id="plan-sections"
              phx-hook="PlanContentHook"
            >
              <%= for {heading, _body, type, rendered} <- @parsed_content.sections, type in [:narrative, :mermaid] do %>
                <div
                  class="plan-section bead-content-section"
                  data-plan-section={heading}
                  data-section-type={type}
                >
                  <h3 :if={type == :narrative} class="plan-section-heading bead-section-heading" data-testid="section-heading">{heading}</h3>
                  <h3 :if={type != :narrative} class="plan-section-heading" data-testid="section-heading">{heading}</h3>
                  <div class={if type == :narrative, do: "plan-section-body bead-content", else: "plan-section-body"}>
                    {render_section(rendered)}
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

          <%= if @dependencies != [] do %>
            <div class="plan-dependencies" data-testid="bead-dependencies">
              <h3>Dependencies ({length(@dependencies)})</h3>
              <div class="plan-dependency-list">
                <%= for dep <- @dependencies do %>
                  <div class="plan-dependency-row" data-testid="dependency-row">
                    <.link
                      patch={"/plans/#{URI.encode_www_form(@project)}/#{URI.encode_www_form(dep.depends_on_id)}"}
                      class="plan-dependency-link"
                    >
                      <span class="plan-dependency-id">{dep.depends_on_id}</span>
                      <span :if={dep.depends_on_title} class="plan-dependency-title">{dep.depends_on_title}</span>
                    </.link>
                    <.status_badge :if={dep.depends_on_status} status={dep.depends_on_status} />
                    <span class="badge badge-muted">{dep.type}</span>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if @annotations != [] do %>
            <div class="plan-annotations" data-testid="bead-annotations">
              <h3>Annotations ({length(@annotations)})</h3>
              <div class="plan-annotation-list">
                <%= for annotation <- @annotations do %>
                  <div class="plan-annotation-item" data-testid="annotation-item">
                    <p class="plan-annotation-text">&ldquo;{annotation.selected_text}&rdquo;</p>
                    <p :if={annotation.comment} class="plan-annotation-comment">{annotation.comment}</p>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <%= if @children != [] do %>
            <div class="plan-children" data-testid="child-tasks">
              <h3>Tasks ({length(@children)})</h3>
              <div class="plan-task-list">
                <%= for task <- @children do %>
                  <.task_row task={task} project={@project} />
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

  defp render_section(html) when is_binary(html), do: Phoenix.HTML.raw(html)

  defp empty_message(false), do: "Plan data is currently unavailable."
  defp empty_message(_), do: "Bead not found."

  defp back_path(nil), do: "/plans"
  defp back_path(project), do: "/plans?project=#{URI.encode_www_form(project)}"
end
