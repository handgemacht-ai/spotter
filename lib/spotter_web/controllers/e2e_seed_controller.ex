defmodule SpotterWeb.E2eSeedController do
  @moduledoc """
  E2E test data seeding controller.

  Provides endpoints to create and clean up deterministic test data
  in Dolt databases for Playwright e2e tests.
  """
  use Phoenix.Controller, formats: [:json]

  require Logger

  alias Spotter.Beads.DoltConfig

  @e2e_project "e2e_plans"
  @e2e_database "e2e_plans"
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
    admin_opts =
      DoltConfig.connection_opts("__admin__")
      |> Keyword.put(:database, "information_schema")

    case MyXQL.start_link(admin_opts) do
      {:ok, conn} ->
        try do
          with :ok <- create_database(conn),
               :ok <- create_tables(conn),
               :ok <- insert_epic(conn),
               :ok <- insert_prereq(conn),
               :ok <- insert_tasks(conn) do
            insert_dependencies(conn)
          end
        after
          GenServer.stop(conn)
        end

      {:error, err} ->
        {:error, err}
    end
  end

  defp create_database(conn) do
    case MyXQL.query(conn, "CREATE DATABASE IF NOT EXISTS `#{@e2e_database}`", []) do
      {:ok, _} -> :ok
      {:error, err} -> {:error, {:create_db, err}}
    end
  end

  defp create_tables(conn) do
    issues_sql = """
    CREATE TABLE IF NOT EXISTS `#{@e2e_database}`.issues (
      id VARCHAR(255) PRIMARY KEY,
      title VARCHAR(1024) NOT NULL,
      status VARCHAR(64) NOT NULL DEFAULT 'open',
      priority INT NOT NULL DEFAULT 2,
      issue_type VARCHAR(64) NOT NULL DEFAULT 'task',
      description LONGTEXT,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME,
      closed_at DATETIME,
      assignee VARCHAR(255)
    )
    """

    deps_sql = """
    CREATE TABLE IF NOT EXISTS `#{@e2e_database}`.dependencies (
      issue_id VARCHAR(255) NOT NULL,
      depends_on_id VARCHAR(255) NOT NULL,
      type VARCHAR(64) NOT NULL DEFAULT 'blocks',
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (issue_id, depends_on_id)
    )
    """

    with {:ok, _} <- MyXQL.query(conn, issues_sql, []),
         {:ok, _} <- MyXQL.query(conn, deps_sql, []) do
      :ok
    else
      {:error, err} -> {:error, {:create_tables, err}}
    end
  end

  defp insert_epic(conn) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    sql = """
    REPLACE INTO `#{@e2e_database}`.issues
      (id, title, status, priority, issue_type, description, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    """

    case MyXQL.query(conn, sql, [
           @e2e_epic_id,
           "Plans Navigation E2E Test Epic",
           "open",
           1,
           "epic",
           @e2e_epic_description,
           now
         ]) do
      {:ok, _} -> :ok
      {:error, err} -> {:error, {:insert_epic, err}}
    end
  end

  defp insert_tasks(conn) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    sql = """
    REPLACE INTO `#{@e2e_database}`.issues
      (id, title, status, priority, issue_type, description, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    """

    Enum.reduce_while(@e2e_tasks, :ok, fn task, :ok ->
      case MyXQL.query(conn, sql, [
             task.id,
             task.title,
             task.status,
             task.priority,
             "task",
             task.description,
             now
           ]) do
        {:ok, _} -> {:cont, :ok}
        {:error, err} -> {:halt, {:error, {:insert_task, task.id, err}}}
      end
    end)
  end

  defp insert_prereq(conn) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    sql = """
    REPLACE INTO `#{@e2e_database}`.issues
      (id, title, status, priority, issue_type, description, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    """

    case MyXQL.query(conn, sql, [
           @e2e_prereq_id,
           "Setup test infrastructure",
           "closed",
           1,
           "task",
           "Prerequisite task for e2e epic.",
           now
         ]) do
      {:ok, _} -> :ok
      {:error, err} -> {:error, {:insert_prereq, err}}
    end
  end

  defp insert_dependencies(conn) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    sql = """
    REPLACE INTO `#{@e2e_database}`.dependencies
      (issue_id, depends_on_id, type, created_at)
    VALUES (?, ?, ?, ?)
    """

    # Tasks depend on epic
    task_deps =
      Enum.reduce_while(@e2e_tasks, :ok, fn task, :ok ->
        case MyXQL.query(conn, sql, [task.id, @e2e_epic_id, "blocks", now]) do
          {:ok, _} -> {:cont, :ok}
          {:error, err} -> {:halt, {:error, {:insert_dep, task.id, err}}}
        end
      end)

    # Epic depends on prereq (so epic detail shows dependencies)
    with :ok <- task_deps do
      case MyXQL.query(conn, sql, [@e2e_epic_id, @e2e_prereq_id, "blocked-by", now]) do
        {:ok, _} -> :ok
        {:error, err} -> {:error, {:insert_dep, @e2e_epic_id, err}}
      end
    end
  end

  defp do_cleanup do
    admin_opts =
      DoltConfig.connection_opts("__admin__")
      |> Keyword.put(:database, "information_schema")

    case MyXQL.start_link(admin_opts) do
      {:ok, conn} ->
        try do
          case MyXQL.query(conn, "DROP DATABASE IF EXISTS `#{@e2e_database}`", []) do
            {:ok, _} -> :ok
            {:error, err} -> {:error, {:drop_db, err}}
          end
        after
          GenServer.stop(conn)
        end

      {:error, err} ->
        {:error, err}
    end
  end
end
