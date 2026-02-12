defmodule SpotterWeb.HeatmapLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{FileHeatmap, Project}

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_heatmap(project, path, opts \\ []) do
    Ash.create!(FileHeatmap, %{
      project_id: project.id,
      relative_path: path,
      change_count_30d: opts[:count] || 1,
      heat_score: opts[:score] || 50.0,
      last_changed_at: opts[:last_changed_at] || ~U[2026-02-01 12:00:00Z]
    })
  end

  describe "top-level route" do
    test "renders heatmap page at /heatmap" do
      {:ok, _view, html} = live(build_conn(), "/heatmap")

      assert html =~ "File heat map"
    end

    test "renders with project filter via query param" do
      project = create_project("heatmap-qp")
      create_heatmap(project, "lib/filtered.ex", score: 60.0)

      {:ok, _view, html} = live(build_conn(), "/heatmap?project_id=#{project.id}")

      assert html =~ "lib/filtered.ex"
    end

    test "invalid project_id falls back to All" do
      {:ok, _view, html} =
        live(build_conn(), "/heatmap?project_id=019c0000-0000-7000-8000-000000000000")

      assert html =~ "File heat map"
      assert html =~ "No file activity data yet"
    end
  end

  describe "populated heatmap" do
    test "renders file rows ranked by heat score" do
      project = create_project("heatmap-pop")
      create_heatmap(project, "lib/hot.ex", score: 85.0, count: 15)
      create_heatmap(project, "lib/cold.ex", score: 10.0, count: 1)

      {:ok, _view, html} = live(build_conn(), "/heatmap?project_id=#{project.id}")

      assert html =~ "lib/hot.ex"
      assert html =~ "lib/cold.ex"
      assert html =~ "85.0"
      assert html =~ "15 changes"
    end

    test "heat badges have correct classes" do
      project = create_project("heatmap-badges")
      create_heatmap(project, "hot.ex", score: 75.0)
      create_heatmap(project, "warm.ex", score: 45.0)
      create_heatmap(project, "mild.ex", score: 20.0)
      create_heatmap(project, "cold.ex", score: 5.0)

      {:ok, _view, html} = live(build_conn(), "/heatmap?project_id=#{project.id}")

      assert html =~ "badge-hot"
      assert html =~ "badge-warm"
      assert html =~ "badge-mild"
      assert html =~ "badge-cold"
    end
  end

  describe "project filtering" do
    test "All shows entries from all projects" do
      p1 = create_project("heatmap-all-a")
      p2 = create_project("heatmap-all-b")
      create_heatmap(p1, "lib/a.ex", score: 50.0)
      create_heatmap(p2, "lib/b.ex", score: 50.0)

      {:ok, _view, html} = live(build_conn(), "/heatmap")

      assert html =~ "lib/a.ex"
      assert html =~ "lib/b.ex"
    end

    test "filter_project event navigates via push_patch" do
      project = create_project("heatmap-filter-proj")
      create_heatmap(project, "lib/only.ex", score: 60.0)

      {:ok, view, _html} = live(build_conn(), "/heatmap")

      html =
        render_click(view, "filter_project", %{"project-id" => project.id})

      assert html =~ "lib/only.ex"
    end
  end

  describe "min score filtering" do
    test "filter_min_score filters out low-score files" do
      project = create_project("heatmap-filter")
      create_heatmap(project, "lib/high.ex", score: 80.0)
      create_heatmap(project, "lib/low.ex", score: 10.0)

      {:ok, view, _html} = live(build_conn(), "/heatmap?project_id=#{project.id}")

      html = render_click(view, "filter_min_score", %{"min_score" => "40"})

      assert html =~ "lib/high.ex"
      refute html =~ "lib/low.ex"
    end
  end

  describe "sorting" do
    test "sort_by change_count_30d reorders files" do
      project = create_project("heatmap-sort")
      create_heatmap(project, "lib/many.ex", score: 30.0, count: 20)
      create_heatmap(project, "lib/few.ex", score: 80.0, count: 2)

      {:ok, view, _html} = live(build_conn(), "/heatmap?project_id=#{project.id}")

      html = render_click(view, "sort_by", %{"field" => "change_count_30d"})

      # many.ex should come first when sorted by change count
      many_pos = :binary.match(html, "lib/many.ex") |> elem(0)
      few_pos = :binary.match(html, "lib/few.ex") |> elem(0)
      assert many_pos < few_pos
    end
  end

  describe "ingest button" do
    test "renders Ingest button on heatmap page" do
      {:ok, _view, html} = live(build_conn(), "/heatmap")

      assert html =~ "Ingest"
    end

    test "ingest progress events update UI" do
      {:ok, view, _html} = live(build_conn(), "/heatmap")

      run_id = Ash.UUID.generate()

      send(view.pid, {:ingest_enqueued, %{run_id: run_id, projects_total: 1, projects: ["test"]}})
      html = render(view)
      assert html =~ "Ingesting"
      assert html =~ "disabled"

      send(
        view.pid,
        {:sync_started, %{run_id: run_id, project: "test", dirs_total: 1, sessions_total: 2}}
      )

      html = render(view)
      assert html =~ "Ingesting"

      send(
        view.pid,
        {:sync_completed,
         %{run_id: run_id, project: "test", dirs_synced: 1, sessions_synced: 2, duration_ms: 100}}
      )

      html = render(view)
      assert html =~ "Ingested"
      refute html =~ "disabled"
    end

    test "ignores stale run_id events" do
      {:ok, view, _html} = live(build_conn(), "/heatmap")

      run_id = Ash.UUID.generate()
      stale_id = Ash.UUID.generate()

      send(view.pid, {:ingest_enqueued, %{run_id: run_id, projects_total: 1, projects: ["test"]}})

      send(
        view.pid,
        {:sync_completed,
         %{run_id: stale_id, project: "test", dirs_synced: 1, sessions_synced: 1, duration_ms: 50}}
      )

      html = render(view)

      # Should still be running since the completed event had a stale run_id
      assert html =~ "Ingesting"
    end
  end

  describe "empty states" do
    test "renders empty message when no data exists" do
      {:ok, _view, html} = live(build_conn(), "/heatmap")

      assert html =~ "No file activity data yet."
      assert html =~ "Click Ingest to import transcripts and compute this heat map."
    end

    test "renders empty message for project with no data" do
      project = create_project("heatmap-empty")

      {:ok, _view, html} = live(build_conn(), "/heatmap?project_id=#{project.id}")

      assert html =~ "No file activity data yet."
    end
  end
end
