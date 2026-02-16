defmodule Spotter.Agents.TestToolsTest do
  use ExUnit.Case, async: false

  alias Spotter.Agents.TestTools.{CreateTest, DeleteTest, ListTests, UpdateTest}
  alias Spotter.TestSpec.Agent.ToolHelpers

  @moduletag :live_dolt

  setup do
    project_id = Ecto.UUID.generate()
    ToolHelpers.set_project_id(project_id)
    ToolHelpers.set_commit_hash("a" |> String.duplicate(40))

    on_exit(fn ->
      ToolHelpers.set_project_id(nil)
      ToolHelpers.set_commit_hash("")
    end)

    # Clean up any leftover test data for this project
    ToolHelpers.dolt_query("DELETE FROM test_specs WHERE project_id = ?", [project_id])

    %{project_id: project_id}
  end

  describe "list_tests" do
    test "returns empty list for no tests", %{project_id: project_id} do
      {:ok, result} =
        ListTests.execute(%{
          "project_id" => project_id,
          "relative_path" => "test/foo_test.exs"
        })

      assert %{"tests" => []} = decode_result(result)
    end
  end

  describe "create_test then list" do
    test "created test appears in list", %{project_id: project_id} do
      {:ok, create_result} =
        CreateTest.execute(%{
          "project_id" => project_id,
          "relative_path" => "test/foo_test.exs",
          "framework" => "ExUnit",
          "test_name" => "returns ok",
          "describe_path" => ["FooTest"],
          "given" => ["a valid input"],
          "when" => ["calling foo/1"],
          "then" => ["returns :ok"],
          "confidence" => 0.9,
          "source_commit_hash" => String.duplicate("a", 40)
        })

      created = decode_result(create_result)["test"]
      assert created["test_name"] == "returns ok"
      assert created["framework"] == "ExUnit"
      assert created["given"] == ["a valid input"]

      {:ok, list_result} =
        ListTests.execute(%{
          "project_id" => project_id,
          "relative_path" => "test/foo_test.exs"
        })

      tests = decode_result(list_result)["tests"]
      assert length(tests) == 1
      assert hd(tests)["id"] == created["id"]
    end
  end

  describe "update_test" do
    test "modifies given/when/then", %{project_id: project_id} do
      {:ok, create_result} =
        CreateTest.execute(%{
          "project_id" => project_id,
          "relative_path" => "test/bar_test.exs",
          "framework" => "ExUnit",
          "test_name" => "original",
          "source_commit_hash" => String.duplicate("a", 40)
        })

      test_id = decode_result(create_result)["test"]["id"]

      {:ok, update_result} =
        UpdateTest.execute(%{
          "project_id" => project_id,
          "relative_path" => "test/bar_test.exs",
          "test_id" => test_id,
          "patch" => %{
            "given" => ["updated given"],
            "when" => ["updated when"],
            "then" => ["updated then"]
          }
        })

      updated = decode_result(update_result)["test"]
      assert updated["given"] == ["updated given"]
      assert updated["when"] == ["updated when"]
      assert updated["then"] == ["updated then"]
    end

    test "returns not_found for wrong file", %{project_id: project_id} do
      {:ok, create_result} =
        CreateTest.execute(%{
          "project_id" => project_id,
          "relative_path" => "test/real_test.exs",
          "framework" => "ExUnit",
          "test_name" => "test1",
          "source_commit_hash" => String.duplicate("a", 40)
        })

      test_id = decode_result(create_result)["test"]["id"]

      {:ok, result} =
        UpdateTest.execute(%{
          "project_id" => project_id,
          "relative_path" => "test/wrong_file.exs",
          "test_id" => test_id,
          "patch" => %{"test_name" => "renamed"}
        })

      assert %{"error" => "test_not_found"} = decode_result(result)
    end
  end

  describe "delete_test" do
    test "removes test", %{project_id: project_id} do
      {:ok, create_result} =
        CreateTest.execute(%{
          "project_id" => project_id,
          "relative_path" => "test/del_test.exs",
          "framework" => "ExUnit",
          "test_name" => "to delete",
          "source_commit_hash" => String.duplicate("a", 40)
        })

      test_id = decode_result(create_result)["test"]["id"]

      {:ok, delete_result} =
        DeleteTest.execute(%{
          "project_id" => project_id,
          "relative_path" => "test/del_test.exs",
          "test_id" => test_id
        })

      assert %{"ok" => true} = decode_result(delete_result)

      {:ok, list_result} =
        ListTests.execute(%{
          "project_id" => project_id,
          "relative_path" => "test/del_test.exs"
        })

      assert %{"tests" => []} = decode_result(list_result)
    end
  end

  defp decode_result(%{"content" => [%{"type" => "text", "text" => json}]}) do
    Jason.decode!(json)
  end
end
