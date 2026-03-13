defmodule Spotter.Beads.BeadStructsTest do
  use ExUnit.Case, async: true

  @epic_module Spotter.Beads.BeadStructs.Epic
  @task_module Spotter.Beads.BeadStructs.Task
  @dep_module Spotter.Beads.BeadStructs.Dependency

  describe "Epic struct" do
    test "from_row/1 maps raw MySQL row to Epic struct" do
      row = %{
        id: "spotter-5zm",
        title: "Plans Navigation",
        status: "open",
        priority: 1,
        issue_type: "epic",
        description: "## Overview\nSpotter feature for viewing epics.",
        created_at: ~N[2026-03-10 08:00:00],
        updated_at: ~N[2026-03-12 14:30:00],
        closed_at: nil,
        assignee: "marco"
      }

      epic = @epic_module.from_row(row)

      assert epic.__struct__ == @epic_module
      assert epic.id == "spotter-5zm"
      assert epic.title == "Plans Navigation"
      assert epic.status == "open"
      assert epic.priority == 1
      assert epic.issue_type == "epic"
      assert epic.description == "## Overview\nSpotter feature for viewing epics."
      assert epic.created_at == ~N[2026-03-10 08:00:00]
      assert epic.updated_at == ~N[2026-03-12 14:30:00]
      assert epic.closed_at == nil
      assert epic.assignee == "marco"
    end

    test "from_row/1 handles nil optional fields" do
      row = %{
        id: "spotter-abc",
        title: "Minimal Epic",
        status: "open",
        priority: 2,
        issue_type: "epic",
        description: nil,
        created_at: ~N[2026-03-10 08:00:00],
        updated_at: nil,
        closed_at: nil,
        assignee: nil
      }

      epic = @epic_module.from_row(row)

      assert epic.__struct__ == @epic_module
      assert epic.description == nil
      assert epic.assignee == nil
      assert epic.updated_at == nil
    end
  end

  describe "Task struct" do
    test "from_row/1 maps raw MySQL row to Task struct" do
      row = %{
        id: "spotter-7vx",
        title: "Bead Data Layer",
        status: "in_progress",
        priority: 1,
        issue_type: "task",
        description: "Implement queries and structs.",
        created_at: ~N[2026-03-11 10:00:00],
        updated_at: ~N[2026-03-13 09:00:00],
        closed_at: nil,
        assignee: "agent-1"
      }

      task = @task_module.from_row(row)

      assert task.__struct__ == @task_module
      assert task.id == "spotter-7vx"
      assert task.title == "Bead Data Layer"
      assert task.status == "in_progress"
      assert task.priority == 1
      assert task.issue_type == "task"
      assert task.assignee == "agent-1"
    end
  end

  describe "Dependency struct" do
    test "from_row/1 maps raw MySQL row to Dependency struct" do
      row = %{
        depends_on_id: "spotter-5zm",
        type: "blocks",
        created_at: ~N[2026-03-10 08:00:00],
        depends_on_title: "Plans Navigation",
        depends_on_status: "open"
      }

      dep = @dep_module.from_row(row)

      assert dep.__struct__ == @dep_module
      assert dep.depends_on_id == "spotter-5zm"
      assert dep.type == "blocks"
      assert dep.depends_on_title == "Plans Navigation"
      assert dep.depends_on_status == "open"
    end

    test "from_row/1 handles nil joined fields" do
      row = %{
        depends_on_id: "spotter-deleted",
        type: "discovered-from",
        created_at: ~N[2026-03-10 08:00:00],
        depends_on_title: nil,
        depends_on_status: nil
      }

      dep = @dep_module.from_row(row)

      assert dep.__struct__ == @dep_module
      assert dep.depends_on_title == nil
      assert dep.depends_on_status == nil
    end
  end

  describe "from_rows/1 batch conversion" do
    test "converts a list of raw rows to Epic structs" do
      rows = [
        %{
          id: "spotter-1",
          title: "First",
          status: "closed",
          priority: 0,
          issue_type: "epic",
          description: "Done",
          created_at: ~N[2026-03-01 00:00:00],
          updated_at: ~N[2026-03-05 00:00:00],
          closed_at: ~N[2026-03-05 00:00:00],
          assignee: nil
        },
        %{
          id: "spotter-2",
          title: "Second",
          status: "open",
          priority: 1,
          issue_type: "epic",
          description: nil,
          created_at: ~N[2026-03-02 00:00:00],
          updated_at: nil,
          closed_at: nil,
          assignee: nil
        }
      ]

      epics = @epic_module.from_rows(rows)

      assert length(epics) == 2
      assert Enum.all?(epics, fn e -> e.__struct__ == @epic_module end)
      assert Enum.map(epics, & &1.id) == ["spotter-1", "spotter-2"]
    end

    test "from_rows/1 returns empty list for empty input" do
      assert [] == @epic_module.from_rows([])
    end
  end
end
