defmodule Spotter.Transcripts.Jobs.ComputeHeatmap do
  @moduledoc "Oban worker that computes file change heatmap for a project."

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id], period: 30]

  require Logger

  alias Spotter.Services.HeatmapCalculator
  alias Spotter.Transcripts.Jobs.ScoreHotspots

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    Logger.info("ComputeHeatmap: computing heatmap for project #{project_id}")

    case HeatmapCalculator.compute(project_id) do
      :ok ->
        enqueue_score_hotspots(project_id)
        :ok

      other ->
        other
    end
  end

  defp enqueue_score_hotspots(project_id) do
    case %{project_id: project_id} |> ScoreHotspots.new() |> Oban.insert() do
      {:ok, _job} ->
        Logger.info("ComputeHeatmap: enqueued ScoreHotspots for project #{project_id}")

      {:error, reason} ->
        Logger.warning(
          "ComputeHeatmap: failed to enqueue ScoreHotspots for project #{project_id}: #{inspect(reason)}"
        )
    end
  end
end
