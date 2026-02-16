defmodule Spotter.Transcripts.Jobs.IngestRecentCommits do
  @moduledoc "Oban worker that backfills recent commits for a project and enqueues hotspot analysis."

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id], period: 600]

  require Ash.Query
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Observability.ErrorReport
  alias Spotter.ProductSpec.Jobs.UpdateRollingSpec
  alias Spotter.Services.GitCommitReader
  alias Spotter.Telemetry.TraceContext
  alias Spotter.Transcripts.{Commit, ProjectIngestState, ReviewItem, Session}
  alias Spotter.Transcripts.Jobs.{AnalyzeCommitHotspots, AnalyzeCommitTests}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id} = args}) do
    limit = Map.get(args, "limit", 10)
    branch = Map.get(args, "branch")

    Tracer.with_span "spotter.ingest_recent_commits.perform" do
      set_span_attributes(project_id, limit, branch, args)

      Logger.info(
        "IngestRecentCommits: ingesting up to #{limit} commits for project #{project_id}"
      )

      case resolve_repo_path(project_id) do
        {:ok, repo_path} ->
          ingest(project_id, repo_path, limit, branch)

        :no_cwd ->
          ErrorReport.set_trace_error(
            "no_accessible_cwd",
            "no_accessible_cwd",
            "transcripts.jobs.ingest_recent_commits"
          )

          Logger.info(
            "IngestRecentCommits: no accessible cwd for project #{project_id}, skipping"
          )

          :ok
      end
    end
  rescue
    error ->
      ErrorReport.set_trace_error(
        "unexpected_error",
        Exception.message(error),
        "transcripts.jobs.ingest_recent_commits"
      )

      reraise error, __STACKTRACE__
  end

  defp set_span_attributes(project_id, limit, branch, args) do
    Tracer.set_attribute("spotter.project_id", project_id)
    Tracer.set_attribute("spotter.limit", limit)
    if is_binary(branch), do: Tracer.set_attribute("spotter.branch", branch)

    if is_binary(args["otel_trace_id"]) and args["otel_trace_id"] != "" do
      Tracer.set_attribute("spotter.parent_trace_id", args["otel_trace_id"])
    end

    if is_binary(args["otel_traceparent"]) and args["otel_traceparent"] != "" do
      Tracer.set_attribute("spotter.parent_traceparent", args["otel_traceparent"])
    end
  rescue
    _error -> :ok
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
        Tracer.set_attribute("spotter.commits_found", length(commit_data))

        Enum.each(commit_data, fn data ->
          upsert_commit_and_review_item(project_id, data)
        end)

        update_ingest_state(project_id)

        Logger.info(
          "IngestRecentCommits: ingested #{length(commit_data)} commits for project #{project_id}"
        )

        :ok

      {:error, reason} ->
        ErrorReport.set_trace_error(
          "recent_commits_failed",
          "recent_commits_failed",
          "transcripts.jobs.ingest_recent_commits"
        )

        Tracer.add_event("recent_commits_error", [{"error.reason", inspect(reason)}])

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
        maybe_enqueue_analyze_tests(project_id, commit)
        maybe_enqueue_rolling_spec(project_id, commit)

      {:error, reason} ->
        Tracer.add_event("commit_upsert_failed", [{"error.reason", inspect(reason)}])
        Logger.warning("IngestRecentCommits: failed to upsert commit: #{inspect(reason)}")
    end
  end

  defp ensure_commit_message_review_item(project_id, commit) do
    existing =
      ReviewItem
      |> Ash.Query.filter(
        project_id == ^project_id and
          target_kind == :commit_message and
          commit_id == ^commit.id
      )
      |> Ash.Query.limit(1)
      |> Ash.read!()

    if existing == [] do
      Ash.create(ReviewItem, %{
        project_id: project_id,
        target_kind: :commit_message,
        commit_id: commit.id,
        importance: :medium,
        interval_days: 4,
        next_due_on: Date.utc_today()
      })
    end
  end

  defp maybe_enqueue_analyze(project_id, commit) do
    if commit.hotspots_status == :pending do
      %{project_id: project_id, commit_hash: commit.commit_hash}
      |> Map.merge(trace_context())
      |> AnalyzeCommitHotspots.new()
      |> Oban.insert()
    end
  end

  defp maybe_enqueue_analyze_tests(project_id, commit) do
    if commit.tests_status == :pending do
      %{project_id: project_id, commit_hash: commit.commit_hash}
      |> Map.merge(trace_context())
      |> AnalyzeCommitTests.new()
      |> Oban.insert()
    end
  end

  defp maybe_enqueue_rolling_spec(project_id, commit) do
    %{project_id: project_id, commit_hash: commit.commit_hash}
    |> Map.merge(trace_context())
    |> UpdateRollingSpec.new()
    |> Oban.insert()
  end

  defp trace_context do
    context = %{run_id: Ash.UUID.generate()}

    trace_id = TraceContext.current_trace_id()
    traceparent = TraceContext.current_traceparent()

    context
    |> then(fn ctx ->
      if is_binary(trace_id), do: Map.put(ctx, :otel_trace_id, trace_id), else: ctx
    end)
    |> then(fn ctx ->
      if is_binary(traceparent), do: Map.put(ctx, :otel_traceparent, traceparent), else: ctx
    end)
  end

  defp update_ingest_state(project_id) do
    Ash.create(ProjectIngestState, %{
      project_id: project_id,
      last_commit_ingest_at: DateTime.utc_now()
    })
  end
end
