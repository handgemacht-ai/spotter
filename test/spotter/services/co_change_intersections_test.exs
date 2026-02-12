defmodule Spotter.Services.CoChangeIntersectionsTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.CoChangeIntersections

  @ts1 ~U[2026-02-10 10:00:00Z]
  @ts2 ~U[2026-02-10 11:00:00Z]
  @ts3 ~U[2026-02-10 12:00:00Z]
  @ts4 ~U[2026-02-10 13:00:00Z]

  describe "compute/2 with file scope" do
    test "acceptance: {A,B,C}, {A,B}, {B,C}, {B,C,D} produces {A,B} freq 2 and {B,C} freq 3" do
      commits = [
        %{hash: "c1", timestamp: @ts1, files: ["a.ex", "b.ex", "c.ex"]},
        %{hash: "c2", timestamp: @ts2, files: ["a.ex", "b.ex"]},
        %{hash: "c3", timestamp: @ts3, files: ["b.ex", "c.ex"]},
        %{hash: "c4", timestamp: @ts4, files: ["b.ex", "c.ex", "d.ex"]}
      ]

      result = CoChangeIntersections.compute(commits, scope: :file)

      ab = Enum.find(result, &(&1.group_key == "a.ex|b.ex"))
      bc = Enum.find(result, &(&1.group_key == "b.ex|c.ex"))

      assert ab != nil
      assert ab.frequency_30d == 2
      assert ab.members == ["a.ex", "b.ex"]

      assert bc != nil
      assert bc.frequency_30d == 3
      assert bc.members == ["b.ex", "c.ex"]
    end

    test "duplicate files within a commit are deduplicated" do
      commits = [
        %{hash: "c1", timestamp: @ts1, files: ["a.ex", "b.ex", "a.ex"]},
        %{hash: "c2", timestamp: @ts2, files: ["a.ex", "b.ex"]}
      ]

      result = CoChangeIntersections.compute(commits, scope: :file)

      ab = Enum.find(result, &(&1.group_key == "a.ex|b.ex"))
      assert ab.frequency_30d == 2
    end

    test "single-file commits do not produce groups" do
      commits = [
        %{hash: "c1", timestamp: @ts1, files: ["a.ex"]},
        %{hash: "c2", timestamp: @ts2, files: ["b.ex"]}
      ]

      assert CoChangeIntersections.compute(commits, scope: :file) == []
    end

    test "binary files are excluded from file-scope grouping" do
      commits = [
        %{hash: "c1", timestamp: @ts1, files: ["a.ex", "logo.png"]},
        %{hash: "c2", timestamp: @ts2, files: ["a.ex", "logo.png"]}
      ]

      # After filtering binary files, each commit has only 1 file => no groups
      assert CoChangeIntersections.compute(commits, scope: :file) == []
    end

    test "output ordering is deterministic: frequency desc, length desc, group_key asc" do
      commits = [
        %{hash: "c1", timestamp: @ts1, files: ["a.ex", "b.ex", "c.ex"]},
        %{hash: "c2", timestamp: @ts2, files: ["a.ex", "b.ex", "c.ex"]},
        %{hash: "c3", timestamp: @ts3, files: ["a.ex", "b.ex"]},
        %{hash: "c4", timestamp: @ts4, files: ["d.ex", "e.ex"]}
      ]

      result = CoChangeIntersections.compute(commits, scope: :file)
      keys = Enum.map(result, & &1.group_key)

      # {a,b} freq 3 (superset {a,b,c} pruned since same freq as {a,b,c} has freq 2)
      # Verify ordering: higher frequency first, then longer members, then alphabetical
      assert keys ==
               Enum.sort_by(keys, fn key ->
                 group = Enum.find(result, &(&1.group_key == key))
                 {-group.frequency_30d, -length(group.members), key}
               end)
    end

    test "last_seen_at is the max timestamp among supporting commits" do
      commits = [
        %{hash: "c1", timestamp: @ts1, files: ["a.ex", "b.ex"]},
        %{hash: "c2", timestamp: @ts3, files: ["a.ex", "b.ex"]}
      ]

      [group] = CoChangeIntersections.compute(commits, scope: :file)
      assert group.last_seen_at == @ts3
    end

    test "minimal-generator pruning removes redundant supersets" do
      # All 3 commits contain {a,b,c}, so {a,b,c} has freq 3
      # {a,b} also has freq 3 (subset of all 3 commits)
      # Since {a,b} is a strict subset of {a,b,c} with same frequency, {a,b,c} is pruned
      commits = [
        %{hash: "c1", timestamp: @ts1, files: ["a.ex", "b.ex", "c.ex"]},
        %{hash: "c2", timestamp: @ts2, files: ["a.ex", "b.ex", "c.ex"]},
        %{hash: "c3", timestamp: @ts3, files: ["a.ex", "b.ex", "c.ex"]}
      ]

      result = CoChangeIntersections.compute(commits, scope: :file)

      # All pairs and the triple have freq 3, so triple and pairs with same freq
      # get pruned down: {a,b} is subset of {a,b,c} with same freq => {a,b,c} dropped
      # But {a,b}, {a,c}, {b,c} all have freq 3 and none is a subset of another pair
      keys = Enum.map(result, & &1.group_key) |> Enum.sort()
      assert keys == ["a.ex|b.ex", "a.ex|c.ex", "b.ex|c.ex"]
    end
  end

  describe "compute/2 with directory scope" do
    test "maps files to their directory names" do
      commits = [
        %{hash: "c1", timestamp: @ts1, files: ["lib/foo.ex", "test/foo_test.exs"]},
        %{hash: "c2", timestamp: @ts2, files: ["lib/bar.ex", "test/bar_test.exs"]}
      ]

      result = CoChangeIntersections.compute(commits, scope: :directory)

      group = Enum.find(result, &(&1.group_key == "lib|test"))
      assert group != nil
      assert group.frequency_30d == 2
      assert group.members == ["lib", "test"]
    end

    test "root-level files map to \".\"" do
      commits = [
        %{hash: "c1", timestamp: @ts1, files: ["mix.exs", "lib/app.ex"]},
        %{hash: "c2", timestamp: @ts2, files: ["mix.exs", "lib/other.ex"]}
      ]

      result = CoChangeIntersections.compute(commits, scope: :directory)

      group = Enum.find(result, &(&1.group_key == ".|lib"))
      assert group != nil
      assert group.frequency_30d == 2
    end

    test "nested directories use full dirname" do
      commits = [
        %{
          hash: "c1",
          timestamp: @ts1,
          files: ["lib/spotter/foo.ex", "test/spotter/foo_test.exs"]
        },
        %{hash: "c2", timestamp: @ts2, files: ["lib/spotter/bar.ex", "test/spotter/bar_test.exs"]}
      ]

      result = CoChangeIntersections.compute(commits, scope: :directory)

      group = Enum.find(result, &(&1.group_key == "lib/spotter|test/spotter"))
      assert group != nil
      assert group.frequency_30d == 2
    end

    test "binary files are NOT excluded from directory scope" do
      commits = [
        %{hash: "c1", timestamp: @ts1, files: ["assets/logo.png", "lib/app.ex"]},
        %{hash: "c2", timestamp: @ts2, files: ["assets/icon.png", "lib/other.ex"]}
      ]

      result = CoChangeIntersections.compute(commits, scope: :directory)

      group = Enum.find(result, &(&1.group_key == "assets|lib"))
      assert group != nil
      assert group.frequency_30d == 2
    end
  end

  describe "compute/2 edge cases" do
    test "empty commits list returns empty" do
      assert CoChangeIntersections.compute([], scope: :file) == []
    end

    test "all commits with single file returns empty" do
      commits = [
        %{hash: "c1", timestamp: @ts1, files: ["a.ex"]},
        %{hash: "c2", timestamp: @ts2, files: ["b.ex"]},
        %{hash: "c3", timestamp: @ts3, files: ["c.ex"]}
      ]

      assert CoChangeIntersections.compute(commits, scope: :file) == []
    end
  end
end
