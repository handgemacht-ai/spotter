defmodule Spotter.Transcripts.Jobs.IngestRecentCommits do
  @moduledoc "Oban worker that backfills recent commits for a project and enqueues hotspot analysis."

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id], period: 600]

  require Ash.Query
  require Logger

  alias Spotter.ProductSpec.Jobs.UpdateRollingSpec
  alias Spotter.Services.GitCommitReader
  alias Spotter.Transcripts.{Commit, ProjectIngestState, ReviewItem, Session}
  alias Spotter.Transcripts.Jobs.AnalyzeCommitHotspots

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id} = args}) do
    limit = Map.get(args, "limit", 10)
    branch = Map.get(args, "branch")

    Logger.info("IngestRecentCommits: ingesting up to #{limit} commits for project #{project_id}")

    case resolve_repo_path(project_id) do
      {:ok, repo_path} ->
        ingest(project_id, repo_path, limit, branch)

      :no_cwd ->
        Logger.info("IngestRecentCommits: no accessible cwd for project #{project_id}, skipping")
        :ok
    end
  end

  defp resolve_repo_path(project_id) do
    case Session
         |> Ash.Query.filter(project_id == ^project_id and not is_nil(cwd))
         |> Ash.Query.sort(started_at: :desc)
         |> Ash.Query.limit(1)
         |> Ash.read!() do
      [session] ->
        if File.dir?(session.cwd), do: {:ok, session.cwd}, else: :no_cwd

      [] ->
        :no_cwd
    end
  end

  defp ingest(project_id, repo_path, limit, branch) do
    opts = [limit: limit] ++ if(branch, do: [branch: branch], else: [])

    case GitCommitReader.recent_commits(repo_path, opts) do
      {:ok, commit_data} ->
        Enum.each(commit_data, fn data ->
          upsert_commit_and_review_item(project_id, data)
        end)

        update_ingest_state(project_id)

        Logger.info(
          "IngestRecentCommits: ingested #{length(commit_data)} commits for project #{project_id}"
        )

        :ok

      {:error, reason} ->
        Logger.warning(
          "IngestRecentCommits: failed for project #{project_id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  defp upsert_commit_and_review_item(project_id, data) do
    case Ash.create(Commit, data) do
      {:ok, commit} ->
        ensure_commit_message_review_item(project_id, commit)
        maybe_enqueue_analyze(project_id, commit)
        maybe_enqueue_rolling_spec(project_id, commit)

      {:error, reason} ->
        Logger.warning("IngestRecentCommits: failed to upsert commit: #{inspect(reason)}")
    end
  end

  defp ensure_commit_message_review_item(project_id, commit) do
    Ash.create(ReviewItem, %{
      project_id: project_id,
      target_kind: :commit_message,
      commit_id: commit.id,
      importance: :medium,
      interval_days: 4,
      next_due_on: Date.add(Date.utc_today(), 4)
    })
  end

  defp maybe_enqueue_analyze(project_id, commit) do
    if commit.hotspots_status == :pending do
      %{project_id: project_id, commit_hash: commit.commit_hash}
      |> AnalyzeCommitHotspots.new()
      |> Oban.insert()
    end
  end

  defp maybe_enqueue_rolling_spec(project_id, commit) do
    if Spotter.ProductSpec.enabled?() do
      %{project_id: project_id, commit_hash: commit.commit_hash}
      |> UpdateRollingSpec.new()
      |> Oban.insert()
    end
  end

  defp update_ingest_state(project_id) do
    Ash.create(ProjectIngestState, %{
      project_id: project_id,
      last_commit_ingest_at: DateTime.utc_now()
    })
  end
end
