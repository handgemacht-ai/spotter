defmodule SpotterWeb.FolderComponentsTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias SpotterWeb.FolderComponents

  @endpoint SpotterWeb.Endpoint

  describe "folder_card/1" do
    test "renders card with label and file count" do
      html =
        render_component(&FolderComponents.folder_card/1,
          folder: %{
            type: :product_skill,
            relative_path: ".claude/skills/product",
            file_count: 7,
            label: "Product Skill"
          },
          project_id: "test-project-id"
        )

      assert html =~ "Product Skill"
      assert html =~ "7 files"
    end

    test "renders link to folder view" do
      html =
        render_component(&FolderComponents.folder_card/1,
          folder: %{
            type: :agent_memory,
            relative_path: ".claude/agent-memory",
            file_count: 4,
            label: "Agent Memory"
          },
          project_id: "proj-123"
        )

      assert html =~ "/projects/proj-123/folders/.claude/agent-memory"
    end
  end

  describe "tree_node/1" do
    test "renders folder node with name" do
      html =
        render_component(&FolderComponents.tree_node/1,
          node: %{
            name: "skills",
            relative_path: ".claude/skills",
            kind: :directory,
            depth: 1,
            expanded: false,
            badge: nil
          },
          project_id: "test-project-id"
        )

      assert html =~ "skills"
    end

    test "renders skill badge when badge is :skill" do
      html =
        render_component(&FolderComponents.tree_node/1,
          node: %{
            name: "product",
            relative_path: ".claude/skills/product",
            kind: :directory,
            depth: 2,
            expanded: false,
            badge: :skill
          },
          project_id: "test-project-id"
        )

      assert html =~ "SKILL"
      assert html =~ "badge-skill"
    end

    test "renders memory badge when badge is :memory" do
      html =
        render_component(&FolderComponents.tree_node/1,
          node: %{
            name: "agent-memory",
            relative_path: ".claude/agent-memory",
            kind: :directory,
            depth: 1,
            expanded: false,
            badge: :memory
          },
          project_id: "test-project-id"
        )

      assert html =~ "MEMORY"
      assert html =~ "badge-memory"
    end
  end
end
