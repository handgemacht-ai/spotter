defmodule Spotter.Plans.BeadsSourceTest do
  use ExUnit.Case, async: false

  import Spotter.Test.OtelHelpers

  @moduletag :live_dolt
  @moduletag timeout: 30_000

  alias Spotter.Plans.BeadsSource

  setup do
    setup_otel_test(%{})
    :ok
  end

  describe "list_projects/0" do
    test "returns project summaries with plan_count field" do
      assert {:ok, summaries} = BeadsSource.list_projects()
      assert is_list(summaries)

      Enum.each(summaries, fn summary ->
        assert is_binary(summary.project)
        assert is_integer(summary.plan_count)
        assert summary.plan_count >= 0
      end)
    end

    test "includes at least the spotter project" do
      assert {:ok, summaries} = BeadsSource.list_projects()
      projects = Enum.map(summaries, & &1.project)
      assert "beads_spotter" in projects
    end
  end

  describe "list_plans/2" do
    test "returns epics as Epic structs for a project" do
      assert {:ok, plans} = BeadsSource.list_plans("beads_spotter", :all)
      assert is_list(plans)

      Enum.each(plans, fn plan ->
        assert %Spotter.Beads.BeadStructs.Epic{} = plan
        assert is_binary(plan.id)
        assert is_binary(plan.title)
        assert plan.issue_type == "epic"
      end)
    end

    test "filters by open status" do
      assert {:ok, plans} = BeadsSource.list_plans("beads_spotter", :open)

      Enum.each(plans, fn plan ->
        assert %Spotter.Beads.BeadStructs.Epic{} = plan
        assert plan.status == "open"
      end)
    end

    test "filters by closed status" do
      assert {:ok, plans} = BeadsSource.list_plans("beads_spotter", :closed)

      Enum.each(plans, fn plan ->
        assert %Spotter.Beads.BeadStructs.Epic{} = plan
        assert plan.status == "closed"
      end)
    end

    test "returns error for nonexistent project" do
      assert {:error, reason} = BeadsSource.list_plans("nonexistent_project_xyz", :all)
      assert reason in [:connection_refused, :unknown_project]
    end
  end

  describe "get_plan/2" do
    test "returns a single epic by ID" do
      {:ok, plans} = BeadsSource.list_plans("beads_spotter", :all)

      case plans do
        [plan | _] ->
          assert {:ok, fetched} = BeadsSource.get_plan("beads_spotter", plan.id)
          assert %Spotter.Beads.BeadStructs.Epic{} = fetched
          assert fetched.id == plan.id
          assert is_binary(fetched.title)
          assert fetched.issue_type == "epic"

        [] ->
          assert {:error, :not_found} = BeadsSource.get_plan("beads_spotter", "nonexistent-999")
      end
    end

    test "returns error for nonexistent plan ID" do
      assert {:error, :not_found} = BeadsSource.get_plan("beads_spotter", "nonexistent-999")
    end
  end

  describe "list_children/2" do
    test "returns child tasks as Task structs" do
      {:ok, plans} = BeadsSource.list_plans("beads_spotter", :all)

      case plans do
        [plan | _] ->
          assert {:ok, children} = BeadsSource.list_children("beads_spotter", plan.id)
          assert is_list(children)

          Enum.each(children, fn child ->
            assert %Spotter.Beads.BeadStructs.Task{} = child
            assert is_binary(child.id)
            assert is_binary(child.title)
          end)

        [] ->
          assert {:ok, []} = BeadsSource.list_children("beads_spotter", "nonexistent-999")
      end
    end

    test "returns empty list for nonexistent parent" do
      assert {:ok, children} = BeadsSource.list_children("beads_spotter", "nonexistent-999")
      assert children == []
    end
  end
end
