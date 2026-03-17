defmodule Spotter.Plans.PlansDependenciesTest do
  use ExUnit.Case, async: false

  import Spotter.Test.OtelHelpers

  alias Spotter.Beads.BeadStructs
  alias Spotter.Plans

  defmodule DepSourceA do
    @behaviour Spotter.Plans.PlanSource

    @impl true
    def list_projects, do: {:ok, [%{project: "dep-project-a", plan_count: 1}]}

    @impl true
    def list_plans(_project, _filter) do
      {:ok,
       [
         %BeadStructs.Epic{
           id: "dep-a-1",
           title: "Epic A",
           status: "open",
           priority: 1,
           issue_type: "epic",
           created_at: ~N[2026-01-01 00:00:00]
         }
       ]}
    end

    @impl true
    def get_plan(_project, plan_id) do
      if plan_id == "dep-a-1" do
        {:ok,
         %BeadStructs.Epic{
           id: "dep-a-1",
           title: "Epic A",
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
    def list_children(_project, _plan_id), do: {:ok, []}

    @impl true
    def list_dependencies(_project, plan_id) do
      if plan_id == "dep-a-1" do
        {:ok,
         [
           %BeadStructs.Dependency{
             depends_on_id: "dep-a-0",
             type: "parent-child",
             created_at: ~N[2026-01-01 00:00:00],
             depends_on_title: "Prereq A",
             depends_on_status: "closed"
           },
           %BeadStructs.Dependency{
             depends_on_id: "dep-a-blocked",
             type: "blocks",
             created_at: ~N[2026-01-01 00:00:00],
             depends_on_title: "Blocker Task",
             depends_on_status: "open"
           }
         ]}
      else
        {:ok, []}
      end
    end
  end

  defmodule DepErrorSource do
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

  describe "list_dependencies/2" do
    test "returns dependencies from first successful source" do
      Application.put_env(:spotter, Spotter.Plans, sources: [DepSourceA])

      assert {:ok, deps} = Plans.list_dependencies("dep-project-a", "dep-a-1")

      assert [
               %BeadStructs.Dependency{depends_on_id: "dep-a-0", type: "parent-child"},
               %BeadStructs.Dependency{depends_on_id: "dep-a-blocked", type: "blocks"}
             ] = deps
    end

    test "falls through to next source on error" do
      Application.put_env(:spotter, Spotter.Plans, sources: [DepErrorSource, DepSourceA])

      assert {:ok, deps} = Plans.list_dependencies("dep-project-a", "dep-a-1")
      assert [%BeadStructs.Dependency{depends_on_id: "dep-a-0"} | _] = deps
    end

    test "returns error when all sources fail" do
      Application.put_env(:spotter, Spotter.Plans, sources: [DepErrorSource])

      assert {:error, :not_found} = Plans.list_dependencies("any", "any")
    end

    test "emits spotter.plans.list_dependencies OTEL span with attributes" do
      Application.put_env(:spotter, Spotter.Plans, sources: [DepSourceA])

      Plans.list_dependencies("dep-project-a", "dep-a-1")

      assert_span_recorded("spotter.plans.list_dependencies")

      assert_span_attributes("spotter.plans.list_dependencies", %{
        "plans.project" => "dep-project-a",
        "plans.plan_id" => "dep-a-1"
      })
    end
  end

  describe "get_bead/2" do
    test "delegates to get_plan/2 and returns same result" do
      Application.put_env(:spotter, Spotter.Plans, sources: [DepSourceA])

      assert {:ok, from_bead} = Plans.get_bead("dep-project-a", "dep-a-1")
      assert {:ok, from_plan} = Plans.get_plan("dep-project-a", "dep-a-1")
      assert from_bead == from_plan
    end

    test "returns error for nonexistent bead" do
      Application.put_env(:spotter, Spotter.Plans, sources: [DepSourceA])

      assert {:error, :not_found} = Plans.get_bead("dep-project-a", "nonexistent-999")
    end
  end
end
