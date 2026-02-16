defmodule Spotter.ProductSpec.Agent.RunnerTest do
  @moduledoc """
  Validation-only tests for ProductSpec Runner input normalization.

  These tests verify the input contract without calling external APIs.
  """

  use ExUnit.Case, async: true

  alias Spotter.Observability.AgentRunInput
  alias Spotter.ProductSpec.Agent.Runner

  @valid_input %{
    project_id: "00000000-0000-0000-0000-000000000042",
    commit_hash: String.duplicate("a", 40),
    commit_subject: "feat: add login page",
    diff_stats: %{files_changed: 1, insertions: 10, deletions: 0, binary_files: []},
    patch_files: [%{path: "lib/app.ex", hunks: []}],
    context_windows: %{"lib/app.ex" => "defmodule App do\nend"}
  }

  @required_keys ~w(project_id commit_hash commit_subject diff_stats patch_files context_windows)a
  @optional_keys [
    {:commit_body, ""},
    {:linked_session_summaries, []},
    {:git_cwd, nil},
    {:run_id, nil}
  ]

  describe "run/1 input validation" do
    test "missing commit_subject returns {:error, {:invalid_input, keys}} with :commit_subject" do
      input = Map.delete(@valid_input, :commit_subject)
      assert {:error, {:invalid_input, keys}} = Runner.run(input)
      assert :commit_subject in keys
    end

    test "missing diff_stats returns {:error, {:invalid_input, keys}} with :diff_stats" do
      input = Map.delete(@valid_input, :diff_stats)
      assert {:error, {:invalid_input, keys}} = Runner.run(input)
      assert :diff_stats in keys
    end

    test "string-key input missing commit_subject fails with :commit_subject in missing keys" do
      input =
        @valid_input
        |> Map.delete(:commit_subject)
        |> Enum.into(%{}, fn {k, v} -> {Atom.to_string(k), v} end)

      assert {:error, {:invalid_input, keys}} = Runner.run(input)
      assert :commit_subject in keys
    end

    test "commit_body is optional and not reported as missing when omitted" do
      input = Map.delete(@valid_input, :commit_body)

      # Use AgentRunInput.normalize directly to test validation without starting SDK
      assert {:ok, normalized} = AgentRunInput.normalize(input, @required_keys, @optional_keys)
      assert normalized.commit_body == ""
    end

    test "linked_session_summaries is optional and not reported as missing when omitted" do
      input = Map.delete(@valid_input, :linked_session_summaries)

      assert {:ok, normalized} = AgentRunInput.normalize(input, @required_keys, @optional_keys)
      assert normalized.linked_session_summaries == []
    end

    test "missing multiple required keys reports all of them" do
      input =
        @valid_input
        |> Map.delete(:commit_subject)
        |> Map.delete(:patch_files)
        |> Map.delete(:context_windows)

      assert {:error, {:invalid_input, keys}} = Runner.run(input)
      assert :commit_subject in keys
      assert :patch_files in keys
      assert :context_windows in keys
    end

    test "empty string commit_subject is treated as missing" do
      input = Map.put(@valid_input, :commit_subject, "")
      assert {:error, {:invalid_input, keys}} = Runner.run(input)
      assert :commit_subject in keys
    end
  end
end
