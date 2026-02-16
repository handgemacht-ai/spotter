defmodule Spotter.Transcripts.Jobs.DistillProjectRollingSummary do
  @moduledoc """
  Oban worker that computes a rolling summary across recent date buckets for a project.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id], period: 600]

  alias Spotter.Services.{GitLogReader, ProjectRollupBucket, ProjectRollupDistiller}
  alias Spotter.Transcripts.{Project, ProjectPeriodSummary, ProjectRollingSummary, Session}

  require Ash.Query
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    Tracer.with_span "spotter.jobs.distill_project_rolling_summary" do
      Tracer.set_attribute("spotter.project_id", project_id)
      do_perform(project_id)
    end
  end

  defp do_perform(project_id) do
    project = Ash.get!(Project, project_id)
    tz = project.timezone || "Etc/UTC"
    bucket_kind = ProjectRollupBucket.bucket_kind_from_env()
    lookback_days = ProjectRollupBucket.lookback_days_from_env()

    case resolve_default_branch(project) do
      {:ok, default_branch} ->
        run_rolling(project, tz, bucket_kind, lookback_days, default_branch)

      {:error, reason} ->
        Logger.warning("DistillProjectRollingSummary: no branch for #{project_id}: #{reason}")

        save_result(
          project,
          tz,
          bucket_kind,
          lookback_days,
          "unknown",
          [],
          "No repo path available."
        )
    end
  end

  defp run_rolling(project, tz, bucket_kind, lookback_days, default_branch) do
    lookback_start_utc = DateTime.add(DateTime.utc_now(), -lookback_days * 86_400, :second)
    start_bucket = ProjectRollupBucket.bucket_key(lookback_start_utc, tz, bucket_kind)

    period_rows =
      load_period_rows(
        project.id,
        bucket_kind,
        tz,
        default_branch,
        start_bucket.bucket_start_date
      )

    if period_rows == [] do
      save_result(
        project,
        tz,
        bucket_kind,
        lookback_days,
        default_branch,
        [],
        "No period summaries in lookback window."
      )
    else
      distill_rolling(project, tz, bucket_kind, lookback_days, default_branch, period_rows)
    end
  end

  defp distill_rolling(project, tz, bucket_kind, lookback_days, default_branch, period_rows) do
    pack = build_rolling_pack(project, bucket_kind, period_rows)
    bucket_dates = Enum.map(period_rows, &to_string(&1.bucket_start_date))

    case ProjectRollupDistiller.distill(pack) do
      {:ok, result} ->
        save_result(
          project,
          tz,
          bucket_kind,
          lookback_days,
          default_branch,
          bucket_dates,
          result.summary_text,
          summary_json: result.summary_json,
          model_used: result.model_used
        )

      {:error, reason} ->
        Logger.warning("DistillProjectRollingSummary: distillation failed: #{inspect(reason)}")

        save_result(
          project,
          tz,
          bucket_kind,
          lookback_days,
          default_branch,
          bucket_dates,
          "Distillation failed."
        )
    end
  end

  defp save_result(
         project,
         tz,
         bucket_kind,
         lookback_days,
         default_branch,
         bucket_dates,
         summary_text,
         extra \\ []
       ) do
    Ash.create!(ProjectRollingSummary, %{
      project_id: project.id,
      bucket_kind: bucket_kind,
      timezone: tz,
      default_branch: default_branch,
      lookback_days: lookback_days,
      included_bucket_start_dates: bucket_dates,
      summary_text: summary_text,
      summary_json: Keyword.get(extra, :summary_json),
      model_used: Keyword.get(extra, :model_used),
      computed_at: DateTime.utc_now()
    })

    :ok
  end

  defp load_period_rows(project_id, bucket_kind, tz, default_branch, start_date) do
    ProjectPeriodSummary
    |> Ash.Query.filter(
      project_id == ^project_id and
        bucket_kind == ^bucket_kind and
        timezone == ^tz and
        default_branch == ^default_branch and
        bucket_start_date >= ^start_date
    )
    |> Ash.Query.sort(bucket_start_date: :asc)
    |> Ash.read!()
  end

  defp build_rolling_pack(project, bucket_kind, period_rows) do
    %{
      project: %{id: project.id, name: project.name, timezone: project.timezone},
      bucket: %{bucket_kind: bucket_kind, rolling: true},
      sessions:
        Enum.map(period_rows, fn row ->
          %{
            session_id: to_string(row.bucket_start_date),
            hook_ended_at: row.computed_at,
            commit_hashes: row.included_commit_hashes,
            distilled_summary: row.summary_text
          }
        end)
    }
  end

  defp resolve_default_branch(project) do
    case find_repo_path(project.id) do
      nil -> {:error, "no session with valid cwd"}
      repo_path -> GitLogReader.resolve_branch(repo_path, nil)
    end
  end

  defp find_repo_path(project_id) do
    Session
    |> Ash.Query.filter(project_id == ^project_id and not is_nil(cwd))
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> case do
      [%{cwd: cwd}] when is_binary(cwd) ->
        if File.dir?(cwd), do: cwd, else: nil

      _ ->
        nil
    end
  end
end
