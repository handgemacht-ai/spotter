defmodule Spotter.Transcripts.Jobs.ScoreHotspots do
  @moduledoc "Oban worker that scores top heatmap files using AI for review prioritization."

  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    unique: [keys: [:project_id], period: 300]

  require Logger
  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Services.HotspotScorer
  alias Spotter.Transcripts.{CodeHotspot, FileHeatmap, Session}

  @top_n 20

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    Tracer.with_span "spotter.score_hotspots.perform" do
      Tracer.set_attribute("spotter.project_id", project_id)

      case resolve_repo_path(project_id) do
        {:ok, repo_path} ->
          entries = top_heatmap_entries(project_id)
          Tracer.set_attribute("spotter.hotspot.entries_total", length(entries))

          Logger.info("ScoreHotspots: scoring #{length(entries)} files for project #{project_id}")

          counters = score_entries(project_id, repo_path, entries)

          Tracer.set_attribute("spotter.hotspot.scored_count", counters.scored)
          Tracer.set_attribute("spotter.hotspot.read_skipped_count", counters.read_skipped)
          Tracer.set_attribute("spotter.hotspot.score_failed_count", counters.score_failed)
          Tracer.set_attribute("spotter.hotspot.persist_failed_count", counters.persist_failed)
          :ok

        :skip ->
          Tracer.set_attribute("spotter.hotspot.entries_total", 0)
          Tracer.set_attribute("spotter.hotspot.scored_count", 0)
          Tracer.set_attribute("spotter.hotspot.read_skipped_count", 0)
          Tracer.set_attribute("spotter.hotspot.score_failed_count", 0)
          Tracer.set_attribute("spotter.hotspot.persist_failed_count", 0)

          Logger.warning("ScoreHotspots: no accessible repo for project #{project_id}, skipping")

          :ok
      end
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
    Enum.reduce(
      entries,
      %{scored: 0, read_skipped: 0, score_failed: 0, persist_failed: 0},
      fn entry, acc ->
        score_single_entry(project_id, repo_path, entry, acc)
      end
    )
  end

  defp score_single_entry(project_id, repo_path, entry, acc) do
    Tracer.with_span "spotter.score_hotspots.file" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.relative_path", entry.relative_path)
      Tracer.set_attribute("spotter.file_heatmap_id", entry.id)

      file_path = Path.join(repo_path, entry.relative_path)

      case File.read(file_path) do
        {:ok, content} ->
          score_and_persist(project_id, entry, content, acc)

        {:error, reason} ->
          Tracer.set_status(:error, "file_read_error: #{inspect(reason)}")

          Logger.debug("ScoreHotspots: skipping #{entry.relative_path}: #{inspect(reason)}")

          %{acc | read_skipped: acc.read_skipped + 1}
      end
    end
  end

  defp score_and_persist(project_id, entry, content, acc) do
    case HotspotScorer.score(entry.relative_path, content) do
      {:ok, %{overall_score: overall_score, rubric: rubric}} ->
        try do
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

          %{acc | scored: acc.scored + 1}
        rescue
          e ->
            Tracer.set_status(:error, "persist_error: #{Exception.message(e)}")

            Logger.warning(
              "ScoreHotspots: persist failed for #{entry.relative_path}: #{Exception.message(e)}"
            )

            %{acc | persist_failed: acc.persist_failed + 1}
        end

      {:error, reason} ->
        Tracer.set_status(:error, "score_error: #{inspect(reason)}")

        Logger.warning(
          "ScoreHotspots: scoring failed for #{entry.relative_path}: #{inspect(reason)}"
        )

        %{acc | score_failed: acc.score_failed + 1}
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

  @max_cwd_candidates 10

  defp resolve_repo_path(project_id) do
    candidates =
      Session
      |> Ash.Query.filter(project_id == ^project_id and not is_nil(cwd))
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(@max_cwd_candidates)
      |> Ash.read!()

    case candidates do
      [] ->
        Logger.warning("ScoreHotspots: no sessions with cwd for project #{project_id}")
        :skip

      sessions ->
        case Enum.find(sessions, fn s -> File.dir?(s.cwd) end) do
          nil ->
            Logger.warning(
              "ScoreHotspots: checked #{length(sessions)} session cwd candidates for project #{project_id}, none accessible"
            )

            :skip

          session ->
            Logger.info(
              "ScoreHotspots: resolved repo path #{session.cwd} for project #{project_id}"
            )

            {:ok, session.cwd}
        end
    end
  end
end
