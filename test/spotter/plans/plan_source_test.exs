defmodule Spotter.Plans.PlanSourceTest do
  use ExUnit.Case, async: true

  alias Spotter.Plans.PlanSource

  describe "behaviour callbacks" do
    test "defines list_projects/0 callback" do
      callbacks = PlanSource.behaviour_info(:callbacks)
      assert {:list_projects, 0} in callbacks
    end

    test "defines list_plans/2 callback" do
      callbacks = PlanSource.behaviour_info(:callbacks)
      assert {:list_plans, 2} in callbacks
    end

    test "defines get_plan/2 callback" do
      callbacks = PlanSource.behaviour_info(:callbacks)
      assert {:get_plan, 2} in callbacks
    end

    test "defines list_children/2 callback" do
      callbacks = PlanSource.behaviour_info(:callbacks)
      assert {:list_children, 2} in callbacks
    end

    test "defines exactly 4 callbacks" do
      callbacks = PlanSource.behaviour_info(:callbacks)
      assert length(callbacks) == 4
    end
  end

  describe "mock implementation" do
    defmodule MockSource do
      @behaviour Spotter.Plans.PlanSource

      @impl true
      def list_projects do
        {:ok, [%{project: "test-project", plan_count: 2}]}
      end

      @impl true
      def list_plans(_project, _filter) do
        {:ok,
         [
           %Spotter.Beads.BeadStructs.Epic{
             id: "bd-1",
             title: "Epic One",
             status: "open",
             priority: 1,
             issue_type: "epic",
             created_at: ~N[2026-01-01 00:00:00]
           }
         ]}
      end

      @impl true
      def get_plan(_project, _plan_id) do
        {:ok,
         %Spotter.Beads.BeadStructs.Epic{
           id: "bd-1",
           title: "Epic One",
           status: "open",
           priority: 1,
           issue_type: "epic",
           created_at: ~N[2026-01-01 00:00:00]
         }}
      end

      @impl true
      def list_children(_project, _plan_id) do
        {:ok,
         [
           %Spotter.Beads.BeadStructs.Task{
             id: "bd-1.1",
             title: "Task One",
             status: "open",
             priority: 2,
             issue_type: "task",
             created_at: ~N[2026-01-01 00:00:00]
           }
         ]}
      end
    end

    test "mock implements list_projects/0 returning project summaries" do
      assert {:ok, [%{project: "test-project", plan_count: 2}]} = MockSource.list_projects()
    end

    test "mock implements list_plans/2 returning epics" do
      assert {:ok, [%Spotter.Beads.BeadStructs.Epic{id: "bd-1"}]} =
               MockSource.list_plans("test-project", :all)
    end

    test "mock implements get_plan/2 returning a single epic" do
      assert {:ok, %Spotter.Beads.BeadStructs.Epic{id: "bd-1", title: "Epic One"}} =
               MockSource.get_plan("test-project", "bd-1")
    end

    test "mock implements list_children/2 returning tasks" do
      assert {:ok, [%Spotter.Beads.BeadStructs.Task{id: "bd-1.1"}]} =
               MockSource.list_children("test-project", "bd-1")
    end

    test "list_plans/2 accepts filter atoms :all, :open, :closed" do
      assert {:ok, _} = MockSource.list_plans("proj", :all)
      assert {:ok, _} = MockSource.list_plans("proj", :open)
      assert {:ok, _} = MockSource.list_plans("proj", :closed)
    end
  end
end
