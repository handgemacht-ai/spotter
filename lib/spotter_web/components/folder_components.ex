defmodule SpotterWeb.FolderComponents do
  @moduledoc """
  Reusable HEEx components for folder/repo tree rendering.

  Provides tree nodes, folder trees, inline file sections, and dashboard
  quick-link cards used by `RepoLive`, `FolderViewLive`, and `PaneListLive`.
  """
  use Phoenix.Component

  @doc "Renders a tree node (file or folder) with icon, badges, indent."
  attr(:node, :map, required: true)
  attr(:project_id, :string, required: true)
  slot(:inner_block)

  def tree_node(assigns) do
    ~H"""
    <div
      class="repo-tree-node"
      style={"padding-left: calc(#{min(max(@node[:depth] || 0, 0), 20)} * 20px)"}
      data-path={@node.relative_path}
      data-kind={@node.kind}
    >
      <span :if={@node.kind == :directory} class={"repo-tree-chevron #{if @node[:expanded], do: "is-expanded"}"}>
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M4 2l4 4-4 4"/></svg>
      </span>
      <span :if={@node.kind == :directory} class="repo-tree-icon repo-tree-icon--folder">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M2 3h4l1 1h7v9H2z"/></svg>
      </span>
      <span :if={@node.kind == :file} class="repo-tree-icon repo-tree-icon--file">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true"><path d="M4 2h5l4 4v8H4z"/><path d="M9 2v4h4"/></svg>
      </span>
      <span class="repo-tree-name">{@node.name}</span>
      <span :if={@node[:badge] == :skill} class="badge badge-skill">SKILL</span>
      <span :if={@node[:badge] == :memory} class="badge badge-memory">MEMORY</span>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "Renders a recursive folder tree."
  attr(:nodes, :list, required: true)
  attr(:project_id, :string, required: true)

  def folder_tree(assigns) do
    ~H"""
    <div class="repo-tree">
      <div :for={node <- @nodes}>
        <.tree_node node={node} project_id={@project_id} />
        <div :if={node[:expanded] && node[:children]} class="repo-tree-children">
          <.folder_tree nodes={node.children} project_id={@project_id} />
        </div>
      </div>
    </div>
    """
  end

  @doc "Renders an inline file section with header + markdown body."
  attr(:file, :map, required: true)
  attr(:project_id, :string, required: true)

  def folder_section(assigns) do
    ~H"""
    <div class="folder-file-section" data-file-path={@file.relative_path}>
      <div class="folder-file-header">
        <a href={"/projects/#{@project_id}/files/#{URI.encode(@file.relative_path)}"}>{@file.relative_path}</a>
      </div>
      <div class="folder-file-body bead-content">
        {Phoenix.HTML.raw(@file.html_content)}
      </div>
    </div>
    """
  end

  @doc "Renders a dashboard quick-link card for a skill/memory folder."
  attr(:folder, :map, required: true)
  attr(:project_id, :string, required: true)

  def folder_card(assigns) do
    assigns = assign(assigns, :card_meta, card_meta(assigns.folder.type))

    ~H"""
    <a
      href={"/projects/#{@project_id}/folders/#{URI.encode(@folder.relative_path)}"}
      class="dashboard-card"
      data-folder-type={@folder.type}
    >
      <div class="dashboard-card-icon" style={"color: #{@card_meta.color}"}>
        {Phoenix.HTML.raw(@card_meta.icon)}
      </div>
      <div class="dashboard-card-label">{@folder.label}</div>
      <div class="dashboard-card-path">{@folder.relative_path}</div>
      <div class="dashboard-card-count">{@folder.file_count} files</div>
    </a>
    """
  end

  defp card_meta(:agent_memory) do
    %{
      color: "var(--accent-purple)",
      icon:
        ~s(<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 2a7 7 0 0 1 7 7c0 2.38-1.19 4.47-3 5.74V17a2 2 0 0 1-2 2h-4a2 2 0 0 1-2-2v-2.26C6.19 13.47 5 11.38 5 9a7 7 0 0 1 7-7z"/><path d="M9 21h6"/><path d="M10 17v4"/><path d="M14 17v4"/></svg>)
    }
  end

  defp card_meta(:product_skill) do
    %{
      color: "var(--accent-blue)",
      icon:
        ~s(<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>)
    }
  end

  defp card_meta(:design_skill) do
    %{
      color: "var(--accent-cyan)",
      icon:
        ~s(<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="13.5" cy="6.5" r=".5" fill="currentColor"/><circle cx="17.5" cy="10.5" r=".5" fill="currentColor"/><circle cx="8.5" cy="7.5" r=".5" fill="currentColor"/><circle cx="6.5" cy="12" r=".5" fill="currentColor"/><path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z"/></svg>)
    }
  end

  defp card_meta(_) do
    %{
      color: "var(--text-tertiary)",
      icon:
        ~s(<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M2 3h4l1 1h7v9H2z"/><path d="M5 8h6"/><path d="M5 11h4"/></svg>)
    }
  end
end
