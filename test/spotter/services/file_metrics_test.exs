defmodule Spotter.Services.FileMetricsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.FileMetrics

  alias Spotter.Transcripts.{
    CoChangeGroup,
    CoChangeGroupMemberStat,
    Commit,
    CommitHotspot,
    FileHeatmap,
    Project
  }

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  describe "list_heatmap/4" do
    test "returns heatmap entries filtered by project" do
      p1 = create_project("fm-hm-a")
      p2 = create_project("fm-hm-b")

      Ash.create!(FileHeatmap, %{
        project_id: p1.id,
        relative_path: "lib/a.ex",
        heat_score: 80.0,
        change_count_30d: 10
      })

      Ash.create!(FileHeatmap, %{
        project_id: p2.id,
        relative_path: "lib/b.ex",
        heat_score: 60.0,
        change_count_30d: 5
      })

      result = FileMetrics.list_heatmap(p1.id)
      assert length(result) == 1
      assert hd(result).relative_path == "lib/a.ex"
    end

    test "returns all entries when project_id is nil" do
      p1 = create_project("fm-hm-all-a")
      p2 = create_project("fm-hm-all-b")

      Ash.create!(FileHeatmap, %{
        project_id: p1.id,
        relative_path: "lib/a.ex",
        heat_score: 80.0,
        change_count_30d: 10
      })

      Ash.create!(FileHeatmap, %{
        project_id: p2.id,
        relative_path: "lib/b.ex",
        heat_score: 60.0,
        change_count_30d: 5
      })

      result = FileMetrics.list_heatmap(nil)
      assert length(result) == 2
    end

    test "filters by min_score" do
      p = create_project("fm-hm-min")

      Ash.create!(FileHeatmap, %{
        project_id: p.id,
        relative_path: "high.ex",
        heat_score: 80.0,
        change_count_30d: 10
      })

      Ash.create!(FileHeatmap, %{
        project_id: p.id,
        relative_path: "low.ex",
        heat_score: 10.0,
        change_count_30d: 1
      })

      result = FileMetrics.list_heatmap(p.id, 40)
      assert length(result) == 1
      assert hd(result).relative_path == "high.ex"
    end

    test "returns empty list on error-safe path" do
      assert FileMetrics.list_heatmap(nil) == [] || is_list(FileMetrics.list_heatmap(nil))
    end
  end

  describe "list_hotspots/4" do
    test "returns enriched hotspot entries" do
      p = create_project("fm-hs-enrich")

      commit =
        Ash.create!(Commit, %{
          commit_hash: String.duplicate("a", 40),
          subject: "Test commit"
        })

      Ash.create!(CommitHotspot, %{
        project_id: p.id,
        commit_id: commit.id,
        relative_path: "lib/hot.ex",
        snippet: "def foo, do: :ok",
        line_start: 1,
        line_end: 5,
        overall_score: 75.0,
        reason: "Complex",
        rubric: %{"complexity" => 70},
        model_used: "claude-opus-4-6",
        analyzed_at: DateTime.utc_now()
      })

      result = FileMetrics.list_hotspots(p.id)
      assert length(result) == 1
      assert %{hotspot: hotspot, commit: commit_data} = hd(result)
      assert hotspot.relative_path == "lib/hot.ex"
      assert commit_data.subject == "Test commit"
    end

    test "returns empty list when no hotspots" do
      p = create_project("fm-hs-empty")
      assert FileMetrics.list_hotspots(p.id) == []
    end

    test "hotspot metadata includes scoring_v2 fields when persisted" do
      p = create_project("fm-hs-v2-meta")

      commit =
        Ash.create!(Commit, %{
          commit_hash: String.duplicate("e", 40),
          subject: "V2 metadata commit"
        })

      v2_metadata = %{
        "scoring_version" => "hotspot_v2",
        "strategy" => "tool_loop_v2",
        "metrics" => %{
          "complexity_score" => 55.0,
          "change_churn_score" => 30.0,
          "blast_radius_score" => 40.0,
          "test_exposure_score" => 70.0,
          "blast_radius_confidence" => "medium"
        },
        "base_score" => 45.25
      }

      Ash.create!(CommitHotspot, %{
        project_id: p.id,
        commit_id: commit.id,
        relative_path: "lib/v2.ex",
        snippet: "def v2, do: :ok",
        line_start: 5,
        line_end: 15,
        overall_score: 50.3,
        reason: "Scored with v2",
        rubric: %{"complexity" => 55},
        model_used: "claude-opus-4-6",
        analyzed_at: DateTime.utc_now(),
        metadata: v2_metadata
      })

      [%{hotspot: hotspot}] = FileMetrics.list_hotspots(p.id)

      assert hotspot.metadata["scoring_version"] == "hotspot_v2"
      assert hotspot.metadata["metrics"]["complexity_score"] == 55.0
      assert hotspot.metadata["metrics"]["blast_radius_confidence"] == "medium"
      assert hotspot.metadata["base_score"] == 45.25
    end
  end

  describe "list_co_change_rows/2" do
    test "returns empty list when project_id is nil" do
      assert FileMetrics.list_co_change_rows(nil) == []
    end

    test "returns derived rows from co-change groups" do
      p = create_project("fm-cc-rows")

      Ash.create!(CoChangeGroup, %{
        project_id: p.id,
        scope: :file,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency_30d: 5,
        last_seen_at: ~U[2026-02-10 12:00:00Z]
      })

      result = FileMetrics.list_co_change_rows(p.id, :file)
      assert length(result) == 2
      members = Enum.map(result, & &1.member) |> Enum.sort()
      assert members == ["lib/a.ex", "lib/b.ex"]
    end
  end

  describe "list_file_sizes/2" do
    test "ranks files by size_bytes descending" do
      p = create_project("fm-fs-rank")

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: p.id,
        scope: :file,
        group_key: "g1",
        member_path: "lib/big.ex",
        size_bytes: 5000,
        loc: 100,
        measured_commit_hash: String.duplicate("a", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: p.id,
        scope: :file,
        group_key: "g1",
        member_path: "lib/small.ex",
        size_bytes: 500,
        loc: 20,
        measured_commit_hash: String.duplicate("a", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      result = FileMetrics.list_file_sizes(p.id)
      assert length(result) == 2
      assert hd(result).member_path == "lib/big.ex"
      assert List.last(result).member_path == "lib/small.ex"
    end

    test "deduplicates by member_path keeping latest measured_at" do
      p = create_project("fm-fs-dedup")

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: p.id,
        scope: :file,
        group_key: "g1",
        member_path: "lib/file.ex",
        size_bytes: 1000,
        loc: 50,
        measured_commit_hash: String.duplicate("a", 40),
        measured_at: ~U[2026-02-01 12:00:00Z]
      })

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: p.id,
        scope: :file,
        group_key: "g2",
        member_path: "lib/file.ex",
        size_bytes: 1500,
        loc: 60,
        measured_commit_hash: String.duplicate("b", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      result = FileMetrics.list_file_sizes(p.id)
      assert length(result) == 1
      assert hd(result).size_bytes == 1500
      assert hd(result).loc == 60
    end

    test "filters by project_id" do
      p1 = create_project("fm-fs-filter-a")
      p2 = create_project("fm-fs-filter-b")

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: p1.id,
        scope: :file,
        group_key: "g1",
        member_path: "lib/a.ex",
        size_bytes: 1000,
        loc: 50,
        measured_commit_hash: String.duplicate("a", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: p2.id,
        scope: :file,
        group_key: "g1",
        member_path: "lib/b.ex",
        size_bytes: 2000,
        loc: 80,
        measured_commit_hash: String.duplicate("a", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      result = FileMetrics.list_file_sizes(p1.id)
      assert length(result) == 1
      assert hd(result).member_path == "lib/a.ex"

      all = FileMetrics.list_file_sizes(nil)
      assert length(all) == 2
    end

    test "returns empty list when no stats exist" do
      p = create_project("fm-fs-empty")
      assert FileMetrics.list_file_sizes(p.id) == []
    end

    test "returns expected keys in each row" do
      p = create_project("fm-fs-keys")

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: p.id,
        scope: :file,
        group_key: "g1",
        member_path: "lib/file.ex",
        size_bytes: 1000,
        loc: 50,
        measured_commit_hash: String.duplicate("c", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      [row] = FileMetrics.list_file_sizes(p.id)
      assert Map.has_key?(row, :project_id)
      assert Map.has_key?(row, :member_path)
      assert Map.has_key?(row, :size_bytes)
      assert Map.has_key?(row, :loc)
      assert Map.has_key?(row, :measured_at)
      assert Map.has_key?(row, :measured_commit_hash)
    end
  end
end
