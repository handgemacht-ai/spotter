defmodule Spotter.Observability.AgentRunInputTest do
  use ExUnit.Case, async: true

  alias Spotter.Observability.AgentRunInput

  describe "fetch_required/2" do
    test "returns value from atom key" do
      assert {:ok, "abc"} = AgentRunInput.fetch_required(%{name: "abc"}, :name)
    end

    test "falls back to string key" do
      assert {:ok, "abc"} = AgentRunInput.fetch_required(%{"name" => "abc"}, :name)
    end

    test "prefers atom key over string key" do
      input = Map.put(%{name: "atom"}, "name", "string")
      assert {:ok, "atom"} = AgentRunInput.fetch_required(input, :name)
    end

    test "returns error for missing key" do
      assert {:error, {:missing_key, :name}} = AgentRunInput.fetch_required(%{}, :name)
    end

    test "treats empty string as missing" do
      assert {:error, {:missing_key, :name}} = AgentRunInput.fetch_required(%{name: ""}, :name)
    end

    test "treats empty string in string key as missing" do
      assert {:error, {:missing_key, :name}} =
               AgentRunInput.fetch_required(%{"name" => ""}, :name)
    end

    test "allows non-string values" do
      assert {:ok, 42} = AgentRunInput.fetch_required(%{count: 42}, :count)
      assert {:ok, [1, 2]} = AgentRunInput.fetch_required(%{"items" => [1, 2]}, :items)
    end
  end

  describe "get_optional/3" do
    test "returns value from atom key" do
      assert AgentRunInput.get_optional(%{name: "abc"}, :name) == "abc"
    end

    test "falls back to string key" do
      assert AgentRunInput.get_optional(%{"name" => "abc"}, :name) == "abc"
    end

    test "returns default when missing" do
      assert AgentRunInput.get_optional(%{}, :name, "default") == "default"
    end

    test "returns nil when missing with no default" do
      assert AgentRunInput.get_optional(%{}, :name) == nil
    end
  end

  describe "normalize/3" do
    test "normalizes atom-key input" do
      input = %{project_id: "p1", commit_hash: "abc123"}

      assert {:ok, %{project_id: "p1", commit_hash: "abc123"}} =
               AgentRunInput.normalize(input, [:project_id, :commit_hash])
    end

    test "normalizes string-key input" do
      input = %{"project_id" => "p1", "commit_hash" => "abc123"}

      assert {:ok, %{project_id: "p1", commit_hash: "abc123"}} =
               AgentRunInput.normalize(input, [:project_id, :commit_hash])
    end

    test "normalizes mixed-key input" do
      input = Map.put(%{project_id: "p1"}, "commit_hash", "abc123")

      assert {:ok, %{project_id: "p1", commit_hash: "abc123"}} =
               AgentRunInput.normalize(input, [:project_id, :commit_hash])
    end

    test "includes optional keys with defaults" do
      input = %{project_id: "p1"}

      assert {:ok, normalized} =
               AgentRunInput.normalize(input, [:project_id], [{:git_cwd, "/tmp"}, :run_id])

      assert normalized.git_cwd == "/tmp"
      assert normalized.run_id == nil
    end

    test "optional keys pick up values from string keys" do
      input = %{"project_id" => "p1", "run_id" => "r1"}

      assert {:ok, normalized} =
               AgentRunInput.normalize(input, [:project_id], [:run_id])

      assert normalized.run_id == "r1"
    end

    test "returns error with missing required keys" do
      input = %{project_id: "p1"}

      assert {:error, {:missing_keys, [:commit_hash]}} =
               AgentRunInput.normalize(input, [:project_id, :commit_hash])
    end

    test "returns error for multiple missing keys" do
      assert {:error, {:missing_keys, [:a, :b]}} =
               AgentRunInput.normalize(%{}, [:a, :b])
    end
  end
end
