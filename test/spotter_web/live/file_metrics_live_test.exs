defmodule SpotterWeb.FileMetricsLiveTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  alias Spotter.Transcripts.{
    CoChangeGroup,
    CoChangeGroupMemberStat,
    Commit,
    CommitHotspot,
    FileHeatmap,
    Project
  }

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  describe "page rendering" do
    test "renders File metrics title at /file-metrics" do
      {:ok, _view, html} = live(build_conn(), "/file-metrics")
      assert html =~ "File metrics"
    end

    test "renders tab bar with all four tabs" do
      {:ok, _view, html} = live(build_conn(), "/file-metrics")
      assert html =~ "Heat map"
      assert html =~ "Hotspots"
      assert html =~ "Co-change"
      assert html =~ "File size"
    end

    test "defaults to heatmap tab" do
      {:ok, _view, html} = live(build_conn(), "/file-metrics")
      assert html =~ "heatmap-section"
      refute html =~ "hotspots-section"
      refute html =~ "co-change-section"
      refute html =~ "file-size-section"
    end

    test "project-scoped route works" do
      project = create_project("fm-proj-route")
      {:ok, _view, html} = live(build_conn(), "/projects/#{project.id}/file-metrics")
      assert html =~ "File metrics"
    end
  end

  describe "tab navigation" do
    test "select_tab switches to hotspots" do
      {:ok, view, _html} = live(build_conn(), "/file-metrics")
      html = render_click(view, "select_tab", %{"tab" => "hotspots"})
      assert html =~ "hotspots-section"
      refute html =~ "heatmap-section"
    end

    test "select_tab switches to co-change" do
      {:ok, view, _html} = live(build_conn(), "/file-metrics")
      html = render_click(view, "select_tab", %{"tab" => "co-change"})
      assert html =~ "co-change-section"
      refute html =~ "heatmap-section"
    end

    test "select_tab switches to file-size" do
      {:ok, view, _html} = live(build_conn(), "/file-metrics")
      html = render_click(view, "select_tab", %{"tab" => "file-size"})
      assert html =~ "file-size-section"
      refute html =~ "heatmap-section"
    end

    test "tab query param renders correct section" do
      {:ok, _view, html} = live(build_conn(), "/file-metrics?tab=hotspots")
      assert html =~ "hotspots-section"
      refute html =~ "heatmap-section"
    end

    test "invalid tab defaults to heatmap" do
      {:ok, _view, html} = live(build_conn(), "/file-metrics?tab=invalid")
      assert html =~ "heatmap-section"
    end

    test "active tab has aria-current=page" do
      {:ok, _view, html} = live(build_conn(), "/file-metrics?tab=co-change")
      assert html =~ ~s(aria-current="page")
    end
  end

  describe "project filtering" do
    test "filter_project event navigates via push_patch" do
      project = create_project("fm-filter")

      Ash.create!(FileHeatmap, %{
        project_id: project.id,
        relative_path: "lib/filtered.ex",
        heat_score: 60.0,
        change_count_30d: 5
      })

      {:ok, view, _html} = live(build_conn(), "/file-metrics")
      html = render_click(view, "filter_project", %{"project-id" => project.id})
      assert html =~ "lib/filtered.ex"
    end

    test "query param selects project" do
      project = create_project("fm-qp")

      Ash.create!(FileHeatmap, %{
        project_id: project.id,
        relative_path: "lib/qp.ex",
        heat_score: 50.0,
        change_count_30d: 3
      })

      {:ok, _view, html} = live(build_conn(), "/file-metrics?project_id=#{project.id}")
      assert html =~ "lib/qp.ex"
    end
  end

  describe "heat map tab" do
    test "renders heatmap entries" do
      project = create_project("fm-hm-entries")

      Ash.create!(FileHeatmap, %{
        project_id: project.id,
        relative_path: "lib/hot.ex",
        heat_score: 85.0,
        change_count_30d: 15
      })

      {:ok, _view, html} = live(build_conn(), "/file-metrics?project_id=#{project.id}")
      assert html =~ "lib/hot.ex"
      assert html =~ "85.0"
      assert html =~ "15 changes"
    end

    test "sorting and filtering still work" do
      project = create_project("fm-hm-sort")

      Ash.create!(FileHeatmap, %{
        project_id: project.id,
        relative_path: "lib/high.ex",
        heat_score: 80.0,
        change_count_30d: 2
      })

      Ash.create!(FileHeatmap, %{
        project_id: project.id,
        relative_path: "lib/low.ex",
        heat_score: 10.0,
        change_count_30d: 1
      })

      {:ok, view, _html} = live(build_conn(), "/file-metrics?project_id=#{project.id}")
      html = render_click(view, "hm_filter_min_score", %{"min_score" => "40"})
      assert html =~ "lib/high.ex"
      refute html =~ "lib/low.ex"
    end

    test "empty state when no heatmap data" do
      {:ok, _view, html} = live(build_conn(), "/file-metrics")
      assert html =~ "No file activity data yet"
    end
  end

  describe "hotspots tab" do
    test "renders hotspot entries" do
      project = create_project("fm-hs-entries")

      commit =
        Ash.create!(Commit, %{
          commit_hash: String.duplicate("a", 40),
          subject: "Test commit"
        })

      Ash.create!(CommitHotspot, %{
        project_id: project.id,
        commit_id: commit.id,
        relative_path: "lib/spotted.ex",
        snippet: "def foo, do: :ok",
        line_start: 1,
        line_end: 10,
        overall_score: 70.0,
        reason: "Complex logic",
        rubric: %{"complexity" => 50},
        model_used: "claude-opus-4-6",
        analyzed_at: DateTime.utc_now()
      })

      {:ok, _view, html} =
        live(build_conn(), "/file-metrics?project_id=#{project.id}&tab=hotspots")

      assert html =~ "lib/spotted.ex"
      assert html =~ "70.0"
    end

    test "analyze_commits enqueues job when project selected" do
      project = create_project("fm-hs-analyze")

      {:ok, view, _html} =
        live(build_conn(), "/file-metrics?project_id=#{project.id}&tab=hotspots")

      _html = render_click(view, "analyze_commits", %{})

      jobs =
        Repo.all(
          from(j in Oban.Job,
            where: j.worker == "Spotter.Transcripts.Jobs.IngestRecentCommits",
            where: j.state == "available"
          )
        )

      assert Enum.any?(jobs, &(&1.args["project_id"] == project.id))
    end

    test "empty state when no hotspots" do
      {:ok, _view, html} = live(build_conn(), "/file-metrics?tab=hotspots")
      assert html =~ "No commit hotspots yet"
    end
  end

  describe "co-change tab" do
    test "shows select project prompt without project" do
      {:ok, _view, html} = live(build_conn(), "/file-metrics?tab=co-change")
      assert html =~ "Select a project to view co-change groups"
    end

    test "renders co-change rows when project selected" do
      project = create_project("fm-cc-rows")

      Ash.create!(CoChangeGroup, %{
        project_id: project.id,
        scope: :file,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency_30d: 5,
        last_seen_at: ~U[2026-02-10 12:00:00Z]
      })

      {:ok, _view, html} =
        live(build_conn(), "/file-metrics?project_id=#{project.id}&tab=co-change")

      assert html =~ "lib/a.ex"
      assert html =~ "lib/b.ex"
    end

    test "scope toggle works" do
      project = create_project("fm-cc-scope")

      Ash.create!(CoChangeGroup, %{
        project_id: project.id,
        scope: :directory,
        group_key: "lib|test",
        members: ["lib", "test"],
        frequency_30d: 8,
        last_seen_at: ~U[2026-02-10 12:00:00Z]
      })

      {:ok, view, html} =
        live(build_conn(), "/file-metrics?project_id=#{project.id}&tab=co-change")

      refute html =~ ~s(\u00d78)

      html = render_click(view, "cc_toggle_scope", %{"scope" => "directory"})
      assert html =~ "lib"
      assert html =~ "test"
      assert html =~ ~s(\u00d78)
    end

    test "expand shows detail panel" do
      project = create_project("fm-cc-expand")

      Ash.create!(CoChangeGroup, %{
        project_id: project.id,
        scope: :file,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency_30d: 5,
        last_seen_at: ~U[2026-02-10 12:00:00Z]
      })

      {:ok, view, _html} =
        live(build_conn(), "/file-metrics?project_id=#{project.id}&tab=co-change")

      html = render_click(view, "cc_toggle_expand", %{"member" => "lib/a.ex"})
      assert html =~ "Members"
      assert html =~ "Relevant Commits"
    end
  end

  describe "file size tab" do
    test "renders LOC and Size columns" do
      project = create_project("fm-fs-cols")

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: project.id,
        scope: :file,
        group_key: "g1",
        member_path: "lib/big.ex",
        size_bytes: 5000,
        loc: 100,
        measured_commit_hash: String.duplicate("a", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      {:ok, _view, html} =
        live(build_conn(), "/file-metrics?project_id=#{project.id}&tab=file-size")

      assert html =~ "lib/big.ex"
      assert html =~ "100"
      assert html =~ "4.9 KB"
    end

    test "ranks by bytes descending by default" do
      project = create_project("fm-fs-rank")

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: project.id,
        scope: :file,
        group_key: "g1",
        member_path: "lib/big.ex",
        size_bytes: 5000,
        loc: 50,
        measured_commit_hash: String.duplicate("a", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: project.id,
        scope: :file,
        group_key: "g1",
        member_path: "lib/small.ex",
        size_bytes: 500,
        loc: 20,
        measured_commit_hash: String.duplicate("a", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      {:ok, _view, html} =
        live(build_conn(), "/file-metrics?project_id=#{project.id}&tab=file-size")

      big_pos = :binary.match(html, "lib/big.ex") |> elem(0)
      small_pos = :binary.match(html, "lib/small.ex") |> elem(0)
      assert big_pos < small_pos
    end

    test "sort toggle for LOC" do
      project = create_project("fm-fs-sort-loc")

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: project.id,
        scope: :file,
        group_key: "g1",
        member_path: "lib/many_lines.ex",
        size_bytes: 500,
        loc: 200,
        measured_commit_hash: String.duplicate("a", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: project.id,
        scope: :file,
        group_key: "g1",
        member_path: "lib/big_bytes.ex",
        size_bytes: 5000,
        loc: 10,
        measured_commit_hash: String.duplicate("a", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      {:ok, view, _html} =
        live(build_conn(), "/file-metrics?project_id=#{project.id}&tab=file-size")

      html = render_click(view, "fs_sort_by", %{"field" => "loc"})

      many_pos = :binary.match(html, "lib/many_lines.ex") |> elem(0)
      big_pos = :binary.match(html, "lib/big_bytes.ex") |> elem(0)
      assert many_pos < big_pos
    end

    test "empty state when no file size data" do
      {:ok, _view, html} = live(build_conn(), "/file-metrics?tab=file-size")
      assert html =~ "No file size data yet"
    end

    test "file links work in project-scoped mode" do
      project = create_project("fm-fs-links")

      Ash.create!(CoChangeGroupMemberStat, %{
        project_id: project.id,
        scope: :file,
        group_key: "g1",
        member_path: "lib/linked.ex",
        size_bytes: 1000,
        loc: 50,
        measured_commit_hash: String.duplicate("a", 40),
        measured_at: ~U[2026-02-10 12:00:00Z]
      })

      {:ok, _view, html} =
        live(build_conn(), "/file-metrics?project_id=#{project.id}&tab=file-size")

      assert html =~ "/projects/#{project.id}/files/lib/linked.ex"
    end
  end

  describe "empty states" do
    test "heatmap empty state renders" do
      project = create_project("fm-empty-hm")
      {:ok, _view, html} = live(build_conn(), "/file-metrics?project_id=#{project.id}")
      assert html =~ "No file activity data yet"
    end

    test "hotspots empty state renders" do
      project = create_project("fm-empty-hs")

      {:ok, _view, html} =
        live(build_conn(), "/file-metrics?project_id=#{project.id}&tab=hotspots")

      assert html =~ "No commit hotspots"
    end

    test "co-change empty state renders" do
      project = create_project("fm-empty-cc")

      {:ok, _view, html} =
        live(build_conn(), "/file-metrics?project_id=#{project.id}&tab=co-change")

      assert html =~ "No co-change groups"
    end

    test "file size empty state renders" do
      {:ok, _view, html} = live(build_conn(), "/file-metrics?tab=file-size")
      assert html =~ "No file size data yet"
    end
  end
end
