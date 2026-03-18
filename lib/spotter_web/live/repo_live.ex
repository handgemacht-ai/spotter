defmodule SpotterWeb.RepoLive do
  @moduledoc "LiveView for browsing the repository tree. Uses sidebar project selector via ProjectContext."
  use Phoenix.LiveView

  alias Spotter.Services.FileDetail
  alias Spotter.Services.SkillFolderReader

  require OpenTelemetry.Tracer

  @max_entries 500
  @initial_depth 3

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Repository",
       tree: [],
       expanded_paths: MapSet.new(),
       error: nil
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, maybe_load_tree(socket)}
  end

  defp maybe_load_tree(socket) do
    if connected?(socket), do: load_for_project(socket), else: socket
  end

  defp load_for_project(socket) do
    case socket.assigns[:current_project_id] do
      nil ->
        assign(socket, error: :no_project)

      project_id ->
        case load_tree(project_id, @initial_depth) do
          {:ok, tree, expanded} ->
            assign(socket, tree: tree, expanded_paths: expanded, error: nil)

          {:error, :no_repo_root} ->
            assign(socket, error: :no_repo_root)

          {:error, _} ->
            assign(socket, error: :load_failed)
        end
    end
  end

  @impl true
  def handle_async({:lazy_load, _}, {:ok, {:ok, children, path}}, socket) do
    tree = insert_children(socket.assigns.tree, path, children)
    expanded = MapSet.put(socket.assigns.expanded_paths, path)
    {:noreply, assign(socket, tree: tree, expanded_paths: expanded)}
  end

  @impl true
  def handle_async({:lazy_load, _}, _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_folder", %{"path" => path}, socket) do
    expanded = socket.assigns.expanded_paths

    if MapSet.member?(expanded, path) do
      {:noreply, assign(socket, expanded_paths: MapSet.delete(expanded, path))}
    else
      node = find_node(socket.assigns.tree, path)

      if node && node.children == nil do
        project_id = socket.assigns.current_project_id

        {:noreply,
         start_async(socket, {:lazy_load, path}, fn ->
           lazy_load_children(project_id, path)
         end)}
      else
        {:noreply, assign(socket, expanded_paths: MapSet.put(expanded, path))}
      end
    end
  end

  def handle_event(event, %{"path" => path}, socket)
      when event in ["navigate_file", "navigate_folder"] do
    project_id = socket.assigns.current_project_id
    encoded = path |> String.split("/") |> Enum.map_join("/", &URI.encode/1)
    segment = if event == "navigate_file", do: "files", else: "folders"
    {:noreply, push_navigate(socket, to: "/projects/#{project_id}/#{segment}/#{encoded}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container" data-testid="repo-root" style="max-width: 800px;">
      <div class="page-header">
        <a href="/" class="back-link">&larr; Back to Dashboard</a>
        <h1>Repository</h1>
      </div>

      <div :if={@error == :no_repo_root} class="empty-state" data-testid="repo-empty">
        No repository found for this project.
      </div>

      <div :if={@error == :no_project} class="empty-state" data-testid="repo-no-project">
        Select a project to browse its repository.
      </div>

      <div :if={@error == :load_failed} class="empty-state" data-testid="repo-error">
        Failed to load repository tree.
      </div>

      <div :if={@error == nil && @tree != []} class="repo-tree" data-testid="repo-tree">
        <.render_tree
          nodes={@tree}
          expanded_paths={@expanded_paths}
          project_id={@current_project_id}
        />
      </div>
    </div>
    """
  end

  defp render_tree(assigns) do
    ~H"""
    <div :for={node <- @nodes}>
      <%= if node.kind == :directory do %>
        <.directory_node
          node={node}
          expanded_paths={@expanded_paths}
          project_id={@project_id}
        />
      <% else %>
        <div
          class="repo-tree-node"
          style={"padding-left: calc(#{node.depth} * 20px)"}
          phx-click="navigate_file"
          phx-value-path={node.relative_path}
          data-testid="repo-tree-file"
          data-path={node.relative_path}
        >
          <span class="repo-tree-icon repo-tree-icon--file">
            <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M4 2h5l4 4v8H4z"/><path d="M9 2v4h4"/></svg>
          </span>
          <span class="repo-tree-name">{node.name}</span>
        </div>
      <% end %>
    </div>
    """
  end

  defp directory_node(assigns) do
    assigns =
      assign(assigns,
        expanded: MapSet.member?(assigns.expanded_paths, assigns.node.relative_path),
        badge: assigns.node.badge
      )

    ~H"""
    <div>
      <div
        class="repo-tree-node"
        style={"padding-left: calc(#{@node.depth} * 20px)"}
        phx-click={click_action(@badge)}
        phx-value-path={@node.relative_path}
        data-testid="repo-tree-folder"
        data-path={@node.relative_path}
        data-badge={@badge}
      >
        <span class={"repo-tree-chevron #{if @expanded, do: "is-expanded"}"}>
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M4 2l4 4-4 4"/></svg>
        </span>
        <span class="repo-tree-icon repo-tree-icon--folder">
          <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M2 3h4l1 1h7v9H2z"/></svg>
        </span>
        <span class="repo-tree-name">{@node.name}</span>
        <span :if={@badge in [:product_skill, :design_skill, :claude_rules]} class="badge badge-skill">SKILL</span>
        <span :if={@badge == :agent_memory} class="badge badge-memory">MEMORY</span>
      </div>
      <div :if={@expanded && @node.children} class="repo-tree-children">
        <.render_tree
          nodes={@node.children}
          expanded_paths={@expanded_paths}
          project_id={@project_id}
        />
      </div>
    </div>
    """
  end

  defp click_action(badge)
       when badge in [:agent_memory, :product_skill, :design_skill, :claude_rules],
       do: "navigate_folder"

  defp click_action(_), do: "toggle_folder"

  # --- Tree Loading ---

  defp load_tree(project_id, max_depth) do
    OpenTelemetry.Tracer.with_span "spotter.repo_live.load_tree",
                                   %{attributes: %{"project.id" => project_id}} do
      case FileDetail.resolve_repo_root(project_id) do
        {:ok, repo_root} ->
          case FileDetail.list_directory(project_id, "") do
            {:ok, entries} ->
              entries = Enum.take(entries, @max_entries)
              {tree, expanded} = build_tree(project_id, repo_root, entries, 0, max_depth)
              OpenTelemetry.Tracer.set_attribute("tree.node_count", count_nodes(tree))
              {:ok, tree, expanded}

            {:error, reason} ->
              {:error, reason}
          end

        {:error, _} ->
          {:error, :no_repo_root}
      end
    end
  end

  defp build_tree(project_id, repo_root, entries, depth, max_depth) do
    {rev_nodes, expanded} =
      Enum.reduce(entries, {[], MapSet.new()}, fn entry, {acc_nodes, acc_expanded} ->
        node = entry_to_node(entry, depth)

        {node, child_expanded} =
          maybe_expand_directory(node, project_id, repo_root, depth, max_depth)

        {[node | acc_nodes], MapSet.union(acc_expanded, child_expanded)}
      end)

    {Enum.reverse(rev_nodes), expanded}
  end

  defp entry_to_node(entry, depth) do
    %{
      name: entry.name,
      relative_path: entry.relative_path,
      kind: entry.kind,
      depth: depth,
      children: nil,
      expanded: false,
      badge: badge_for(entry)
    }
  end

  defp maybe_expand_directory(%{kind: :directory} = node, project_id, repo_root, depth, max_depth)
       when depth < max_depth do
    case FileDetail.list_directory(project_id, node.relative_path) do
      {:ok, child_entries} ->
        child_entries = Enum.take(child_entries, @max_entries)

        {children, child_expanded} =
          build_tree(project_id, repo_root, child_entries, depth + 1, max_depth)

        expanded = MapSet.put(child_expanded, node.relative_path)
        {%{node | children: children, expanded: true}, expanded}

      {:error, _} ->
        {%{node | children: [], expanded: true}, MapSet.new()}
    end
  end

  defp maybe_expand_directory(node, _project_id, _repo_root, _depth, _max_depth) do
    {node, MapSet.new()}
  end

  defp badge_for(%{kind: :directory, relative_path: path}) do
    case SkillFolderReader.classify_folder(path) do
      :custom -> nil
      type -> type
    end
  end

  defp badge_for(_), do: nil

  defp lazy_load_children(project_id, path) do
    case FileDetail.list_directory(project_id, path) do
      {:ok, entries} ->
        depth = path |> String.split("/") |> length()

        children =
          entries
          |> Enum.take(@max_entries)
          |> Enum.map(&entry_to_node(&1, depth))

        {:ok, children, path}

      error ->
        error
    end
  end

  defp insert_children(tree, target_path, children) do
    Enum.map(tree, fn node ->
      cond do
        node.relative_path == target_path ->
          %{node | children: children, expanded: true}

        node.kind == :directory && node.children != nil ->
          %{node | children: insert_children(node.children, target_path, children)}

        true ->
          node
      end
    end)
  end

  defp find_node([], _path), do: nil

  defp find_node([node | rest], path) do
    cond do
      node.relative_path == path ->
        node

      node.kind == :directory && node.children != nil ->
        find_node(node.children, path) || find_node(rest, path)

      true ->
        find_node(rest, path)
    end
  end

  defp count_nodes(nodes) do
    Enum.reduce(nodes, 0, fn node, acc ->
      child_count = if node.children, do: count_nodes(node.children), else: 0
      acc + 1 + child_count
    end)
  end
end
