defmodule Spotter.PlansTest do
  use ExUnit.Case, async: false

  import Spotter.Test.OtelHelpers

  alias Spotter.Plans

  # --- Stub sources implementing PlanSource behaviour ---

  alias Spotter.Beads.BeadStructs

  defmodule SourceA do
    @behaviour Spotter.Plans.PlanSource

    @impl true
    def list_projects do
      {:ok, [%{project: "project-a", plan_count: 3}]}
    end

    @impl true
    def list_plans(_project, _filter) do
      {:ok,
       [
         %BeadStructs.Epic{
           id: "a-1",
           title: "Epic from A",
           status: "open",
           priority: 1,
           issue_type: "epic",
           created_at: ~N[2026-01-01 00:00:00]
         }
       ]}
    end

    @impl true
    def get_plan(_project, plan_id) do
      if plan_id == "a-1" do
        {:ok,
         %BeadStructs.Epic{
           id: "a-1",
           title: "Epic from A",
           status: "open",
           priority: 1,
           issue_type: "epic",
           created_at: ~N[2026-01-01 00:00:00]
         }}
      else
        {:error, :not_found}
      end
    end

    @impl true
    def list_children(_project, plan_id) do
      if plan_id == "a-1" do
        {:ok,
         [
           %BeadStructs.Task{
             id: "a-1.1",
             title: "Task from A",
             status: "open",
             priority: 2,
             issue_type: "task",
             created_at: ~N[2026-01-01 00:00:00]
           }
         ]}
      else
        {:ok, []}
      end
    end

    @impl true
    def list_dependencies(_project, _plan_id), do: {:ok, []}
  end

  defmodule SourceB do
    @behaviour Spotter.Plans.PlanSource

    @impl true
    def list_projects do
      {:ok, [%{project: "project-b", plan_count: 1}]}
    end

    @impl true
    def list_plans(_project, _filter) do
      {:ok,
       [
         %BeadStructs.Epic{
           id: "b-1",
           title: "Epic from B",
           status: "open",
           priority: 2,
           issue_type: "epic",
           created_at: ~N[2026-02-01 00:00:00]
         }
       ]}
    end

    @impl true
    def get_plan(_project, plan_id) do
      if plan_id == "b-1" do
        {:ok,
         %BeadStructs.Epic{
           id: "b-1",
           title: "Epic from B",
           status: "open",
           priority: 2,
           issue_type: "epic",
           created_at: ~N[2026-02-01 00:00:00]
         }}
      else
        {:error, :not_found}
      end
    end

    @impl true
    def list_children(_project, plan_id) do
      if plan_id == "b-1" do
        {:ok,
         [
           %BeadStructs.Task{
             id: "b-1.1",
             title: "Task from B",
             status: "open",
             priority: 1,
             issue_type: "task",
             created_at: ~N[2026-02-01 00:00:00]
           }
         ]}
      else
        {:ok, []}
      end
    end

    @impl true
    def list_dependencies(_project, _plan_id), do: {:ok, []}
  end

  defmodule ErrorSource do
    @behaviour Spotter.Plans.PlanSource

    @impl true
    def list_projects, do: {:error, :connection_refused}

    @impl true
    def list_plans(_project, _filter), do: {:error, :connection_refused}

    @impl true
    def get_plan(_project, _plan_id), do: {:error, :connection_refused}

    @impl true
    def list_children(_project, _plan_id), do: {:error, :connection_refused}

    @impl true
    def list_dependencies(_project, _plan_id), do: {:error, :connection_refused}
  end

  setup do
    setup_otel_test(%{})
    original = Application.get_env(:spotter, Spotter.Plans)

    on_exit(fn ->
      if original do
        Application.put_env(:spotter, Spotter.Plans, original)
      else
        Application.delete_env(:spotter, Spotter.Plans)
      end
    end)

    :ok
  end

  describe "list_projects/0" do
    test "aggregates projects from multiple configured sources" do
      Application.put_env(:spotter, Spotter.Plans, sources: [SourceA, SourceB])

      assert {:ok, projects} = Plans.list_projects()
      project_names = Enum.map(projects, & &1.project)

      assert "project-a" in project_names
      assert "project-b" in project_names
      assert length(projects) == 2
    end

    test "swallows errors from individual sources and returns others" do
      Application.put_env(:spotter, Spotter.Plans, sources: [SourceA, ErrorSource])

      assert {:ok, projects} = Plans.list_projects()
      assert [%{project: "project-a", plan_count: 3}] = projects
    end

    test "returns empty list when all sources error" do
      Application.put_env(:spotter, Spotter.Plans, sources: [ErrorSource])

      assert {:ok, []} = Plans.list_projects()
    end

    test "emits spotter.plans.list_projects OTEL span" do
      Application.put_env(:spotter, Spotter.Plans, sources: [SourceA])

      Plans.list_projects()

      assert_span_recorded("spotter.plans.list_projects")
    end
  end

  describe "list_plans/2" do
    test "returns plans from first successful source" do
      Application.put_env(:spotter, Spotter.Plans, sources: [SourceA, SourceB])

      assert {:ok, plans} = Plans.list_plans("project-a", :all)
      assert [%BeadStructs.Epic{id: "a-1", title: "Epic from A"}] = plans
    end

    test "falls through to next source on error" do
      Application.put_env(:spotter, Spotter.Plans, sources: [ErrorSource, SourceB])

      assert {:ok, plans} = Plans.list_plans("project-b", :all)
      assert [%BeadStructs.Epic{id: "b-1"}] = plans
    end

    test "returns error when all sources fail" do
      Application.put_env(:spotter, Spotter.Plans, sources: [ErrorSource])

      assert {:error, :not_found} = Plans.list_plans("any", :all)
    end

    test "emits spotter.plans.list_plans OTEL span with attributes" do
      Application.put_env(:spotter, Spotter.Plans, sources: [SourceA])

      Plans.list_plans("project-a", :open)

      assert_span_recorded("spotter.plans.list_plans")

      assert_span_attributes("spotter.plans.list_plans", %{
        "plans.project" => "project-a",
        "plans.filter" => "open"
      })
    end
  end

  describe "get_plan/2" do
    test "returns plan from first source that has it" do
      Application.put_env(:spotter, Spotter.Plans, sources: [SourceA, SourceB])

      assert {:ok, %BeadStructs.Epic{id: "a-1", title: "Epic from A"}} =
               Plans.get_plan("project-a", "a-1")
    end

    test "falls through to next source when first returns not_found" do
      Application.put_env(:spotter, Spotter.Plans, sources: [SourceA, SourceB])

      assert {:ok, %BeadStructs.Epic{id: "b-1", title: "Epic from B"}} =
               Plans.get_plan("project-b", "b-1")
    end

    test "returns error when no source has the plan" do
      Application.put_env(:spotter, Spotter.Plans, sources: [SourceA, SourceB])

      assert {:error, :not_found} = Plans.get_plan("any", "nonexistent-999")
    end

    test "emits spotter.plans.get_plan OTEL span with attributes" do
      Application.put_env(:spotter, Spotter.Plans, sources: [SourceA])

      Plans.get_plan("project-a", "a-1")

      assert_span_recorded("spotter.plans.get_plan")

      assert_span_attributes("spotter.plans.get_plan", %{
        "plans.project" => "project-a",
        "plans.plan_id" => "a-1"
      })
    end
  end

  describe "list_children/2" do
    test "returns children from first successful source" do
      Application.put_env(:spotter, Spotter.Plans, sources: [SourceA])

      assert {:ok, children} = Plans.list_children("project-a", "a-1")
      assert [%BeadStructs.Task{id: "a-1.1", title: "Task from A"}] = children
    end

    test "falls through to next source on error" do
      Application.put_env(:spotter, Spotter.Plans, sources: [ErrorSource, SourceA])

      assert {:ok, children} = Plans.list_children("project-a", "a-1")
      assert [%BeadStructs.Task{id: "a-1.1"}] = children
    end

    test "returns error when all sources fail" do
      Application.put_env(:spotter, Spotter.Plans, sources: [ErrorSource])

      assert {:error, :not_found} = Plans.list_children("any", "any")
    end

    test "emits spotter.plans.list_children OTEL span with attributes" do
      Application.put_env(:spotter, Spotter.Plans, sources: [SourceA])

      Plans.list_children("project-a", "a-1")

      assert_span_recorded("spotter.plans.list_children")

      assert_span_attributes("spotter.plans.list_children", %{
        "plans.project" => "project-a",
        "plans.plan_id" => "a-1"
      })
    end
  end

  describe "default config" do
    test "uses BeadsSource when no sources configured" do
      Application.delete_env(:spotter, Spotter.Plans)

      # The module should still be callable — it defaults to [BeadsSource]
      # We can't assert specific results (Dolt may not be running),
      # but the function should not raise
      result = Plans.list_projects()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
