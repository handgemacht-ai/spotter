defmodule SpotterWeb.PlanDetailLive do
  @moduledoc "LiveView for displaying a single bead's detail with parsed sections, mermaid diagrams, dependencies, annotations, and child tasks."
  use Phoenix.LiveView

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  import SpotterWeb.PlanComponents
  import SpotterWeb.AnnotationComponents

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
       selection: nil,
       highlighted_annotation: nil
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
  def handle_event(
        "plan_text_selected",
        %{"selected_text" => text, "comment" => comment} = params,
        socket
      )
      when is_binary(comment) and comment != "" do
    %{bead: bead, project: project} = socket.assigns

    socket =
      case maybe_create_annotation(bead, project, text, comment) do
        :ok -> assign(socket, annotations: fetch_annotations(bead.id), selection: nil)
        _ -> assign(socket, selection: %{text: text, section: params["section"]})
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("plan_text_selected", %{"selected_text" => text} = params, socket) do
    {:noreply, assign(socket, selection: %{text: text, section: params["section"]})}
  end

  @impl true
  def handle_event("save_annotation", %{"comment" => comment}, socket) do
    %{bead: bead, project: project, selection: selection} = socket.assigns

    socket =
      if selection do
        case maybe_create_annotation(bead, project, selection.text, comment) do
          :ok -> assign(socket, annotations: fetch_annotations(bead.id), selection: nil)
          _ -> assign(socket, selection: nil)
        end
      else
        assign(socket, selection: nil)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("highlight_annotation", %{"id" => id}, socket) do
    {:noreply, assign(socket, highlighted_annotation: id)}
  end

  @impl true
  def handle_event("delete_annotation", %{"id" => id}, socket) do
    Tracer.with_span "spotter.plan_detail.delete_annotation" do
      Tracer.set_attribute("spotter.annotation.id", id)

      case Spotter.Transcripts.Annotation
           |> Ash.get(id) do
        {:ok, annotation} ->
          Ash.destroy!(annotation)
          annotations = Enum.reject(socket.assigns.annotations, &(&1.id == id))
          {:noreply, assign(socket, annotations: annotations, highlighted_annotation: nil)}

        _ ->
          {:noreply, socket}
      end
    end
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
      classification:
        description
        |> BeadContentParser.extract_classification()
        |> Enum.map(fn {k, v} -> {k, List.wrap(v)} end)
    }
  end

  defp fetch_data(project, bead_id) do
    case lookup_test_fixture(project, bead_id) do
      %{} = fixture ->
        fetch_from_fixture(fixture, project, bead_id)

      nil ->
        fetch_from_dolt(project, bead_id)
    end
  end

  defp fetch_from_fixture(fixture, project, bead_id) do
    bead = BeadStructs.Epic.from_row(fixture.epic)
    children = BeadStructs.Task.from_rows(fixture.children)

    deps =
      case Map.get(fixture, :dependencies) do
        nil -> safe_call(fn -> Plans.list_dependencies(project, bead_id) end, [])
        dep_maps -> BeadStructs.Dependency.from_rows(dep_maps)
      end

    annotations = fetch_annotations(bead_id)
    {bead, children, deps, annotations}
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

    annotations_task = Task.async(fn -> fetch_annotations(bead_id) end)

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
          <.bead_header bead={@bead} />

          <%= if @parsed_content do %>
            <.classification_chips items={@parsed_content.classification} />

            <div
              data-testid="bead-sections"
              id="plan-sections"
              phx-hook="PlanContentHook"
              data-annotations={encode_annotations(@annotations)}
            >
              <%= for {heading, _body, type, rendered} <- @parsed_content.sections, type == :narrative do %>
                <div
                  class="plan-section bead-content-section"
                  data-plan-section={heading}
                  data-section-type={type}
                >
                  <h3
                    class="plan-section-heading bead-section-heading"
                    data-testid="section-heading"
                  >
                    {heading}
                  </h3>
                  <div class="plan-section-body bead-content">
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

              <.acceptance_cards rows={@parsed_content.acceptance_rows} />
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

          <.dependency_list deps={@dependencies} project={@project} />

          <div
            :if={@annotations != []}
            class="bead-annotations-section"
            data-testid="bead-annotations"
            data-highlighted-annotation={@highlighted_annotation}
          >
            <h4 class="bead-section-heading">Annotations ({length(@annotations)})</h4>
            <.annotation_cards annotations={@annotations} />
          </div>

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

  defp encode_annotations([]), do: nil

  defp encode_annotations(annotations) do
    annotations
    |> Enum.map(fn a -> %{id: a.id, selected_text: a.selected_text, comment: a.comment} end)
    |> Jason.encode!()
  end

  defp render_section(html) when is_binary(html), do: Phoenix.HTML.raw(html)

  defp empty_message(false), do: "Plan data is currently unavailable."
  defp empty_message(_), do: "Bead not found."

  defp back_path(nil), do: "/plans"
  defp back_path(project), do: "/plans?project=#{URI.encode_www_form(project)}"
end
