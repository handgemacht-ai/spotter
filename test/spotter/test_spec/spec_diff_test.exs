defmodule Spotter.TestSpec.SpecDiffTest do
  use ExUnit.Case, async: true

  alias Spotter.TestSpec.SpecDiff

  defp test_entry(overrides \\ %{}) do
    Map.merge(
      %{
        id: "1",
        project_id: "p1",
        test_key: "ExUnit|test/foo_test.exs|Describe|my test",
        relative_path: "test/foo_test.exs",
        framework: "ExUnit",
        describe_path: ["Describe"],
        test_name: "my test",
        line_start: 10,
        line_end: 20,
        given: ["a thing"],
        when: ["called"],
        then: ["returns ok"],
        confidence: 0.9,
        metadata: %{},
        source_commit_hash: "abc123",
        updated_by_git_commit: "abc123"
      },
      overrides
    )
  end

  describe "diff/2" do
    test "empty lists produce no diff" do
      assert %{added: [], removed: [], changed: []} = SpecDiff.diff([], [])
    end

    test "detects added tests" do
      to = [test_entry()]
      result = SpecDiff.diff([], to)

      assert length(result.added) == 1
      assert result.removed == []
      assert result.changed == []
      assert hd(result.added).test_key == "ExUnit|test/foo_test.exs|Describe|my test"
    end

    test "detects removed tests" do
      from = [test_entry()]
      result = SpecDiff.diff(from, [])

      assert result.added == []
      assert length(result.removed) == 1
      assert result.changed == []
    end

    test "detects changed semantic fields" do
      from = [test_entry()]
      to = [test_entry(%{test_name: "renamed test", line_start: 15})]

      result = SpecDiff.diff(from, to)

      assert result.added == []
      assert result.removed == []
      assert length(result.changed) == 1

      change = hd(result.changed)
      assert :test_name in change.changed_fields
      assert :line_start in change.changed_fields
    end

    test "ignores updated_by_git_commit changes" do
      from = [test_entry()]
      to = [test_entry(%{updated_by_git_commit: "different_hash"})]

      result = SpecDiff.diff(from, to)

      assert result.added == []
      assert result.removed == []
      assert result.changed == []
    end

    test "handles mixed add/remove/change" do
      kept = test_entry(%{test_key: "keep"})
      removed_entry = test_entry(%{test_key: "old"})
      added_entry = test_entry(%{test_key: "new"})
      changed_entry = test_entry(%{test_key: "keep", confidence: 0.5})

      result = SpecDiff.diff([kept, removed_entry], [changed_entry, added_entry])

      assert length(result.added) == 1
      assert hd(result.added).test_key == "new"

      assert length(result.removed) == 1
      assert hd(result.removed).test_key == "old"

      assert length(result.changed) == 1
      assert hd(result.changed).test_key == "keep"
      assert :confidence in hd(result.changed).changed_fields
    end
  end
end
