defmodule SpotterWeb.E2eSeedController do
  @moduledoc """
  E2E test data seeding controller.

  Provides endpoints to create and clean up deterministic test data
  as JSONL files for Playwright e2e tests.
  """
  use Phoenix.Controller, formats: [:json]

  require Logger

  alias Spotter.Beads.JsonlStore

  @e2e_project "e2e_plans"
  @e2e_epic_id "e2e-epic-001"

  @e2e_epic_description """
  ## Overview

  This is a deterministic test epic for e2e Plans Navigation tests.
  It exercises all parsed content features.

  ## Architecture

  The system uses a LiveView frontend backed by Dolt beads queries.
  PlansLive shows project filter chips and an epic table.
  PlanDetailLive renders sections, mermaid diagrams, acceptance tables, and child tasks.

  ```yaml
  stack:
    frontend: Phoenix LiveView
    backend: Elixir + Ash
    database: Dolt (MySQL-compatible)
  ```

  ## Diagram

  ```mermaid
  graph TD
    A[PlansLive] --> B[BeadQueries]
    B --> C[Dolt Database]
    A --> D[PlanDetailLive]
    D --> B
  ```

  ## Classification

  - Type: feature
  - Architecture Change: true
  - Boundary Operation: none
  - Affected Boundaries: lib/spotter_web/live, lib/spotter/beads

  ## Acceptance Criteria

  | GIVEN | WHEN | THEN |
  |-------|------|------|
  | A project with epics exists | User selects the project chip | Epic table shows the project's epics |
  | An epic has child tasks | User views the epic detail | Child tasks are listed with expand/collapse |
  | An epic has mermaid blocks | User views the epic detail | Mermaid diagrams are rendered |
  """

  @e2e_prereq_id "e2e-prereq-001"

  @e2e_tasks [
    %{
      id: "e2e-task-001",
      title: "Implement project filter chips",
      status: "closed",
      priority: 1,
      description: "Add filter chips to PlansLive for project selection."
    },
    %{
      id: "e2e-task-002",
      title: "Add epic table with sorting",
      status: "in_progress",
      priority: 1,
      description: "Display epics in a sortable table with status and priority badges."
    },
    %{
      id: "e2e-task-003",
      title: "Build plan detail view",
      status: "open",
      priority: 2,
      description: "Create PlanDetailLive with sections, mermaid, and acceptance table."
    }
  ]

  def seed_plans(conn, %{"scenario" => "plans-navigation"}) do
    case do_seed() do
      :ok ->
        json(conn, %{status: "ok", project: @e2e_project, epic_id: @e2e_epic_id})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{status: "error", reason: inspect(reason)})
    end
  end

  def seed_plans(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{status: "error", reason: "unknown scenario"})
  end

  def cleanup_plans(conn, _params) do
    case do_cleanup() do
      :ok ->
        json(conn, %{status: "ok"})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{status: "error", reason: inspect(reason)})
    end
  end

  defp do_seed do
    path = e2e_backup_path()
    File.mkdir_p!(path)

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

    issues = build_issues(now)
    deps = build_dependencies(now)

    issues_path = Path.join(path, "issues.jsonl")
    deps_path = Path.join(path, "dependencies.jsonl")

    File.write!(issues_path, encode_jsonl(issues))
    File.write!(deps_path, encode_jsonl(deps))

    :ok
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp do_cleanup do
    path = e2e_backup_path()

    if File.dir?(path) do
      File.rm_rf!(path)
    end

    :ok
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp e2e_backup_path do
    base =
      JsonlStore.backup_path(@e2e_project) ||
        Path.join([System.tmp_dir!(), "spotter_e2e", @e2e_project, "backup"])

    base
  end

  defp build_issues(now) do
    epic = %{
      "id" => @e2e_epic_id,
      "title" => "Plans Navigation E2E Test Epic",
      "status" => "open",
      "priority" => 1,
      "issue_type" => "epic",
      "description" => @e2e_epic_description,
      "created_at" => now,
      "updated_at" => nil,
      "closed_at" => nil,
      "assignee" => nil
    }

    prereq = %{
      "id" => @e2e_prereq_id,
      "title" => "Setup test infrastructure",
      "status" => "closed",
      "priority" => 1,
      "issue_type" => "task",
      "description" => "Prerequisite task for e2e epic.",
      "created_at" => now,
      "updated_at" => nil,
      "closed_at" => nil,
      "assignee" => nil
    }

    tasks =
      Enum.map(@e2e_tasks, fn task ->
        %{
          "id" => task.id,
          "title" => task.title,
          "status" => task.status,
          "priority" => task.priority,
          "issue_type" => "task",
          "description" => task.description,
          "created_at" => now,
          "updated_at" => nil,
          "closed_at" => nil,
          "assignee" => nil
        }
      end)

    [epic, prereq | tasks]
  end

  defp build_dependencies(now) do
    task_deps =
      Enum.map(@e2e_tasks, fn task ->
        %{
          "issue_id" => task.id,
          "depends_on_id" => @e2e_epic_id,
          "type" => "parent-child",
          "created_at" => now
        }
      end)

    extra = [
      %{
        "issue_id" => "e2e-task-003",
        "depends_on_id" => "e2e-task-002",
        "type" => "blocks",
        "created_at" => now
      },
      %{
        "issue_id" => @e2e_epic_id,
        "depends_on_id" => @e2e_prereq_id,
        "type" => "blocked-by",
        "created_at" => now
      }
    ]

    task_deps ++ extra
  end

  defp encode_jsonl(items) do
    items
    |> Enum.map_join("\n", &Jason.encode!/1)
  end
end
