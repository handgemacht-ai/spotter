defmodule Spotter.Transcripts.Jobs.ScoreHotspots do
  @moduledoc "Oban worker that scores top heatmap files using AI for review prioritization."

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    unique: [keys: [:project_id], period: 300]

  require Logger
  require Ash.Query

  alias Spotter.Services.HotspotScorer
  alias Spotter.Transcripts.{CodeHotspot, FileHeatmap, Session}

  @top_n 20

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    case resolve_repo_path(project_id) do
      {:ok, repo_path} ->
        entries = top_heatmap_entries(project_id)
        Logger.info("ScoreHotspots: scoring #{length(entries)} files for project #{project_id}")
        score_entries(project_id, repo_path, entries)
        :ok

      :skip ->
        Logger.warning("ScoreHotspots: no accessible repo for project #{project_id}, skipping")
        :ok
    end
  end

  defp top_heatmap_entries(project_id) do
    FileHeatmap
    |> Ash.Query.filter(project_id == ^project_id and heat_score > 0)
    |> Ash.Query.sort(heat_score: :desc)
    |> Ash.Query.limit(@top_n)
    |> Ash.read!()
  end

  defp score_entries(project_id, repo_path, entries) do
    Enum.each(entries, fn entry ->
      file_path = Path.join(repo_path, entry.relative_path)

      case File.read(file_path) do
        {:ok, content} ->
          score_and_persist(project_id, entry, content)

        {:error, reason} ->
          Logger.debug("ScoreHotspots: skipping #{entry.relative_path}: #{inspect(reason)}")
      end
    end)
  end

  defp score_and_persist(project_id, entry, content) do
    case HotspotScorer.score(entry.relative_path, content) do
      {:ok, %{overall_score: overall_score, rubric: rubric}} ->
        Ash.create!(CodeHotspot, %{
          project_id: project_id,
          file_heatmap_id: entry.id,
          relative_path: entry.relative_path,
          snippet: extract_snippet(content),
          line_start: 1,
          line_end: min(line_count(content), 500),
          overall_score: overall_score,
          rubric: rubric,
          model_used: "claude-haiku-4-5-20251001",
          scored_at: DateTime.utc_now()
        })

      {:error, reason} ->
        Logger.warning(
          "ScoreHotspots: scoring failed for #{entry.relative_path}: #{inspect(reason)}"
        )
    end
  end

  defp extract_snippet(content) do
    content
    |> String.split("\n")
    |> Enum.take(50)
    |> Enum.join("\n")
  end

  defp line_count(content) do
    content |> String.split("\n") |> length()
  end

  defp resolve_repo_path(project_id) do
    case Session
         |> Ash.Query.filter(project_id == ^project_id and not is_nil(cwd))
         |> Ash.Query.sort(inserted_at: :desc)
         |> Ash.Query.limit(1)
         |> Ash.read!() do
      [session] ->
        if File.dir?(session.cwd) do
          {:ok, session.cwd}
        else
          Logger.warning("ScoreHotspots: cwd #{session.cwd} not accessible")
          :skip
        end

      [] ->
        :skip
    end
  end
end
