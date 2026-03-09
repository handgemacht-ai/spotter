defmodule Spotter.Beads.ClientTest do
  use ExUnit.Case, async: false

  import Spotter.Test.OtelHelpers

  @moduletag :live_dolt
  @moduletag timeout: 30_000

  alias Spotter.Beads.Client

  setup do
    setup_otel_test(%{})
    :ok
  end

  describe "start_link/1 and basic connectivity" do
    test "starts a pool and executes SELECT 1" do
      assert {:ok, _result} = Client.query("spotter", "SELECT 1")

      # TELEMETRY: query span emitted with correct attributes
      assert_span_attributes("spotter.beads.client.query", %{
        "spotter.beads.query_name" => "raw"
      })
    end
  end

  describe "list_epics/2" do
    test "returns {:ok, list} of epic issues and emits span" do
      assert {:ok, epics} = Client.list_epics("spotter", :all)
      assert is_list(epics)

      # TELEMETRY: list_epics span with database and query_name attributes
      assert_span_attributes("spotter.beads.client.list_epics", %{
        "spotter.beads.database" => "beads_spotter",
        "spotter.beads.query_name" => "list_epics"
      })
    end

    test "filters by open status" do
      assert {:ok, epics} = Client.list_epics("spotter", :open)
      assert is_list(epics)

      Enum.each(epics, fn epic ->
        assert epic.status == "open"
      end)
    end

    test "filters by closed status" do
      assert {:ok, epics} = Client.list_epics("spotter", :closed)
      assert is_list(epics)

      Enum.each(epics, fn epic ->
        assert epic.status == "closed"
      end)
    end

    test "returns epics with expected fields" do
      assert {:ok, epics} = Client.list_epics("spotter", :all)

      case epics do
        [epic | _] ->
          assert Map.has_key?(epic, :id)
          assert Map.has_key?(epic, :title)
          assert Map.has_key?(epic, :status)
          assert Map.has_key?(epic, :priority)
          assert Map.has_key?(epic, :issue_type)
          assert epic.issue_type == "epic"

        [] ->
          :ok
      end
    end
  end

  describe "get_issue/2" do
    test "returns {:ok, issue} for existing bead ID" do
      {:ok, epics} = Client.list_epics("spotter", :all)

      case epics do
        [epic | _] ->
          assert {:ok, issue} = Client.get_issue("spotter", epic.id)
          assert issue.id == epic.id
          assert is_binary(issue.title)

          # TELEMETRY: get_issue span emitted
          assert_span_attributes("spotter.beads.client.get_issue", %{
            "spotter.beads.database" => "beads_spotter",
            "spotter.beads.query_name" => "get_issue"
          })

        [] ->
          assert {:error, :not_found} = Client.get_issue("spotter", "nonexistent-999")
      end
    end

    test "returns {:error, :not_found} for nonexistent bead ID" do
      assert {:error, :not_found} = Client.get_issue("spotter", "nonexistent-999")

      # TELEMETRY: span still emitted for not_found case
      assert_span_recorded("spotter.beads.client.get_issue")
    end
  end

  describe "get_children/2" do
    test "returns {:ok, list} of child issues for a parent and emits span" do
      {:ok, epics} = Client.list_epics("spotter", :all)

      case epics do
        [epic | _] ->
          assert {:ok, children} = Client.get_children("spotter", epic.id)
          assert is_list(children)

          # TELEMETRY: get_children span with correct attributes
          assert_span_attributes("spotter.beads.client.get_children", %{
            "spotter.beads.database" => "beads_spotter",
            "spotter.beads.query_name" => "get_children"
          })

        [] ->
          assert {:ok, []} = Client.get_children("spotter", "nonexistent-999")
      end
    end

    test "returns {:ok, []} for bead with no children" do
      assert {:ok, children} = Client.get_children("spotter", "nonexistent-999")
      assert children == []
    end
  end

  describe "epic_counts_by_project/0" do
    test "returns a map of project_name => count and emits span" do
      assert {:ok, counts} = Client.epic_counts_by_project()
      assert is_map(counts)

      Enum.each(counts, fn {project, count} ->
        assert is_binary(project)
        assert is_integer(count)
        assert count >= 0
      end)

      # TELEMETRY: epic_counts_by_project span emitted
      assert_span_attributes("spotter.beads.client.epic_counts_by_project", %{
        "spotter.beads.query_name" => "epic_counts_by_project"
      })
    end
  end

  describe "get_dependencies/2" do
    test "returns {:ok, list} of dependencies and emits span" do
      {:ok, epics} = Client.list_epics("spotter", :all)

      case epics do
        [epic | _] ->
          assert {:ok, deps} = Client.get_dependencies("spotter", epic.id)
          assert is_list(deps)

          # TELEMETRY: get_dependencies span with correct attributes
          assert_span_attributes("spotter.beads.client.get_dependencies", %{
            "spotter.beads.database" => "beads_spotter",
            "spotter.beads.query_name" => "get_dependencies"
          })

        [] ->
          assert {:ok, []} = Client.get_dependencies("spotter", "nonexistent-999")
      end
    end
  end

  describe "error handling" do
    test "returns {:error, :connection_refused} for invalid project" do
      assert {:error, reason} = Client.list_epics("nonexistent_project", :all)
      assert reason in [:connection_refused, :unknown_project]
    end
  end
end
