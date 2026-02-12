defmodule Spotter.Transcripts.Jobs.ComputeHeatmapTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{FileHeatmap, FileSnapshot, Project, Session}
  alias Spotter.Transcripts.Jobs.ComputeHeatmap

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_session(project) do
    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "test-dir",
      project_id: project.id
    })
  end

  test "perform/1 computes heatmap and enqueues ScoreHotspots" do
    project = create_project("job-test")
    project_id = project.id
    session = create_session(project)

    Ash.create!(FileSnapshot, %{
      session_id: session.id,
      tool_use_id: Ash.UUID.generate(),
      file_path: "lib/mod.ex",
      relative_path: "lib/mod.ex",
      change_type: :modified,
      source: :edit,
      timestamp: DateTime.utc_now()
    })

    assert :ok = ComputeHeatmap.perform(%Oban.Job{args: %{"project_id" => project_id}})

    heatmaps =
      FileHeatmap
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.read!()

    assert length(heatmaps) == 1
    assert hd(heatmaps).relative_path == "lib/mod.ex"
    assert hd(heatmaps).heat_score > 0

    # Verify ScoreHotspots was enqueued
    import Ecto.Query

    assert [%{args: %{"project_id" => ^project_id}}] =
             Repo.all(
               from(j in Oban.Job,
                 where: j.worker == "Spotter.Transcripts.Jobs.ScoreHotspots",
                 where: j.state == "available"
               )
             )
  end

  test "perform/1 succeeds for empty project and still enqueues ScoreHotspots" do
    import Ecto.Query

    project = create_project("job-empty")
    project_id = project.id

    assert :ok = ComputeHeatmap.perform(%Oban.Job{args: %{"project_id" => project_id}})

    assert [] =
             FileHeatmap
             |> Ash.Query.filter(project_id == ^project_id)
             |> Ash.read!()

    # ScoreHotspots should still be enqueued even for empty projects
    assert [%{args: %{"project_id" => ^project_id}}] =
             Repo.all(
               from(j in Oban.Job,
                 where: j.worker == "Spotter.Transcripts.Jobs.ScoreHotspots",
                 where: j.state == "available"
               )
             )
  end
end
