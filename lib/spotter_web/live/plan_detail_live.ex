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
       highlighted_annotation: nil,
       active_sidebar_tab: :annotations,
       graph_data: nil,
       graph_expanded: false,
       preview_image: nil
     )}
  end

  @impl true
  def handle_params(%{"project" => project, "bead_id" => bead_id}, _uri, socket) do
    socket =
      if connected?(socket) do
        socket
        |> assign(project: project, selection: nil, highlighted_annotation: nil)
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
    socket =
      socket
      |> assign(selection: %{text: text, section: params["section"]})
      |> maybe_focus_annotations_tab()

    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_sidebar_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_sidebar_tab: String.to_existing_atom(tab))}
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
        {:ok, %{bead_id: bead_id} = annotation} when bead_id == socket.assigns.bead.id ->
          Ash.destroy!(annotation)
          annotations = Enum.reject(socket.assigns.annotations, &(&1.id == id))
          {:noreply, assign(socket, annotations: annotations, highlighted_annotation: nil)}

        _ ->
          {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_event("dep_graph_navigate", %{"bead_id" => bead_id}, socket) do
    path =
      "/plans/#{URI.encode_www_form(socket.assigns.project)}/#{URI.encode_www_form(bead_id)}"

    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("toggle_dep_graph", _params, socket) do
    {:noreply, assign(socket, graph_expanded: !socket.assigns.graph_expanded)}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, selection: nil)}
  end

  @impl true
  def handle_event("plan_image_clicked", %{"src" => src, "alt" => alt}, socket) do
    {:noreply,
     assign(socket, preview_image: %{src: src, alt: alt}, active_sidebar_tab: :image)}
  end

  @impl true
  def handle_event("close_image_preview", _params, socket) do
    {:noreply, assign(socket, preview_image: nil, active_sidebar_tab: :annotations)}
  end

  defp maybe_focus_annotations_tab(socket) do
    socket
    |> assign(active_sidebar_tab: :annotations)
    |> push_event("annotations_attention", %{})
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

      {bead, children, deps, annotations, graph} = fetch_data(project, bead_id)

      parsed = parse_bead_content(bead && bead.description)

      dolt_available = bead != nil

      graph_data = build_graph_payload(graph, bead_id)

      Tracer.set_attribute("spotter.plan_detail.dolt_available", dolt_available)
      Tracer.set_attribute("spotter.plan_detail.child_count", length(children))
      Tracer.set_attribute("spotter.plan_detail.dep_count", length(deps))
      Tracer.set_attribute("spotter.plan_detail.annotation_count", length(annotations))
      Tracer.set_attribute("spotter.plan_detail.has_graph", graph_data != nil)

      socket =
        assign(socket,
          bead: bead,
          children: children,
          dependencies: deps,
          annotations: annotations,
          parsed_content: parsed,
          dolt_available: dolt_available,
          graph_data: graph_data
        )

      if graph_data do
        push_event(socket, "dep_graph_data", graph_data)
      else
        socket
      end
    end
  end

  defp parse_bead_content(nil), do: nil

  defp parse_bead_content(description) do
    sections =
      case BeadContentParser.extract_sections_ordered(description) do
        [] when is_binary(description) and description != "" ->
          trimmed = String.trim(description)

          if trimmed != "" do
            rendered = BeadContentParser.render_section_body(trimmed)
            [{"Description", trimmed, :narrative, rendered}]
          else
            []
          end

        ordered ->
          Enum.map(ordered, fn {heading, body} ->
            type = BeadContentParser.classify_section(heading)
            rendered = BeadContentParser.render_section_body(body)
            {heading, body, type, rendered}
          end)
      end

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

    graph = Map.get(fixture, :graph)
    annotations = fetch_annotations(bead_id)
    {bead, children, deps, annotations, graph}
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

    graph_task =
      Task.async(fn -> safe_call(fn -> Plans.dependency_graph(project, bead_id) end, nil) end)

    annotations_task = Task.async(fn -> fetch_annotations(bead_id) end)

    bead = Task.await(bead_task, @query_timeout)
    children = Task.await(children_task, @query_timeout)
    deps = Task.await(deps_task, @query_timeout)
    graph = Task.await(graph_task, @query_timeout)
    annotations = Task.await(annotations_task, @query_timeout)

    {bead, children, deps, annotations, graph}
  end

  defp fetch_annotations(bead_id) do
    case Spotter.Transcripts.Annotation
         |> Ash.Query.for_read(:list_for_bead, %{bead_id: bead_id})
         |> Ash.read() do
      {:ok, annotations} -> annotations
      _ -> []
    end
  end

  defp build_graph_payload(nil, _bead_id), do: nil

  defp build_graph_payload(%{nodes: nodes, edges: edges}, bead_id) do
    js_nodes =
      Enum.map(nodes, fn n ->
        %{
          id: n.id,
          title: n.title,
          status: n.status,
          type: n.issue_type
        }
      end)

    js_edges =
      Enum.map(edges, fn e ->
        %{from: e.from, to: e.to, type: e.type}
      end)

    %{nodes: js_nodes, edges: js_edges, current_id: bead_id}
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

          <%= if @graph_data do %>
            <button
              class="dep-graph-toggle"
              phx-click="toggle_dep_graph"
              data-testid="dep-graph-toggle"
            >
              {if @graph_expanded, do: "Hide", else: "Show"} dependency graph ({length(@graph_data.nodes)} beads)
            </button>
            <div
              id="dep-graph"
              phx-hook="DepGraphHook"
              class={["dep-graph-container", @graph_expanded && "is-expanded"]}
              data-testid="dep-graph"
              data-graph={Jason.encode!(@graph_data)}
            >
            </div>
          <% end %>

          <div class="plan-detail-layout">
            <div class="plan-detail-content">
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

            <div class="plan-detail-sidebar" data-testid="plan-detail-sidebar">
              <div class="sidebar-tabs">
                <button
                  id="sidebar-tab-annotations"
                  class={"sidebar-tab #{if @active_sidebar_tab == :annotations, do: "is-active"}"}
                  phx-click="switch_sidebar_tab"
                  phx-value-tab="annotations"
                >
                  Annotations ({length(@annotations)})
                </button>
                <button
                  :if={@preview_image}
                  id="sidebar-tab-image"
                  class={"sidebar-tab #{if @active_sidebar_tab == :image, do: "is-active"}"}
                  phx-click="switch_sidebar_tab"
                  phx-value-tab="image"
                  data-testid="sidebar-tab-image"
                >
                  Image
                </button>
              </div>
              <div
                :if={@active_sidebar_tab == :annotations}
                class="sidebar-tab-content"
                data-highlighted-annotation={@highlighted_annotation}
              >
                <.annotation_editor
                  :if={@selection}
                  selected_text={@selection.text}
                  selection_label="Selected plan text"
                />
                <.annotation_cards annotations={@annotations} />
              </div>
              <div
                :if={@active_sidebar_tab == :image && @preview_image}
                class="sidebar-tab-content sidebar-image-preview"
                data-testid="sidebar-image-preview"
              >
                <div class="sidebar-image-header">
                  <span :if={@preview_image.alt != ""} class="sidebar-image-alt">
                    {@preview_image.alt}
                  </span>
                  <button
                    class="btn-ghost text-xs"
                    phx-click="close_image_preview"
                    data-testid="close-image-preview"
                  >
                    &times;
                  </button>
                </div>
                <img
                  src={@preview_image.src}
                  alt={@preview_image.alt}
                  class="sidebar-image-img"
                  data-testid="sidebar-image-img"
                  loading="lazy"
                />
                <a
                  href={@preview_image.src}
                  target="_blank"
                  rel="noopener noreferrer"
                  class="sidebar-image-link"
                >
                  Open original
                </a>
              </div>
            </div>
          </div>
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
