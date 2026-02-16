defmodule Spotter.Transcripts.Jobs.DistillCompletedSession do
  @moduledoc """
  Oban worker that distills a completed session into a structured summary.

  Only sessions with at least one SessionCommitLink are distilled.
  Sessions without commit links are marked as skipped.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:session_id], period: 86_400, states: Oban.Job.unique_states(:incomplete)]

  alias Spotter.Services.{ProjectRollupBucket, SessionDistillationPack, SessionDistiller}

  alias Spotter.Transcripts.Jobs.{
    DistillProjectPeriodSummary,
    DistillProjectRollingSummary,
    SyncTranscripts
  }

  alias Spotter.Transcripts.{Session, SessionCommitLink, SessionDistillation}

  require Ash.Query
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"session_id" => session_id}}) do
    Tracer.with_span "spotter.jobs.distill_completed_session" do
      Tracer.set_attribute("spotter.session_id", session_id)
      do_perform(session_id)
    end
  end

  defp do_perform(session_id) do
    SyncTranscripts.sync_session_by_id(session_id)

    case load_session(session_id) do
      nil ->
        Logger.warning("DistillCompletedSession: session not found: #{session_id}")
        :ok

      session ->
        distill_session(session)
    end
  end

  defp distill_session(session) do
    cond do
      is_nil(session.hook_ended_at) ->
        skip_session(session, "not_ended")

      not has_commit_links?(session) ->
        skip_session(session, "no_commit_links")

      true ->
        run_distillation(session)
    end
  end

  defp run_distillation(session) do
    pack = SessionDistillationPack.build(session)

    case SessionDistiller.distill(pack) do
      {:ok, result} ->
        save_completed(session, result, pack)

      {:error, reason} ->
        raw = if is_tuple(reason) and tuple_size(reason) >= 3, do: elem(reason, 2), else: nil
        save_error(session, reason, raw)
    end
  end

  defp save_completed(session, result, pack) do
    Ash.create!(SessionDistillation, %{
      session_id: session.id,
      status: :completed,
      model_used: result.model_used,
      summary_json: result.summary_json,
      summary_text: result.summary_text,
      raw_response_text: result.raw_response_text,
      input_stats: pack.stats
    })

    Ash.update!(session, %{
      distilled_summary: result.summary_json["session_summary"],
      distilled_status: :completed,
      distilled_model_used: result.model_used,
      distilled_at: DateTime.utc_now()
    })

    enqueue_rollups(session)
    :ok
  end

  defp skip_session(session, reason) do
    Ash.create!(SessionDistillation, %{
      session_id: session.id,
      status: :skipped,
      error_reason: reason
    })

    Ash.update!(session, %{distilled_status: :skipped})
    :ok
  end

  defp save_error(session, reason, raw_response_text) do
    Logger.warning("DistillCompletedSession: distillation failed: #{inspect(reason)}")
    Tracer.set_status(:error, inspect(reason))

    Ash.create!(SessionDistillation, %{
      session_id: session.id,
      status: :error,
      error_reason: inspect(reason),
      raw_response_text: raw_response_text
    })

    Ash.update!(session, %{distilled_status: :error})
    :ok
  end

  defp enqueue_rollups(session) do
    session = Ash.load!(session, :project)
    tz = session.project.timezone || "Etc/UTC"
    kind = ProjectRollupBucket.bucket_kind_from_env()
    bucket = ProjectRollupBucket.bucket_key(session.hook_ended_at, tz, kind)

    %{
      project_id: session.project_id,
      bucket_kind: to_string(bucket.bucket_kind),
      bucket_start_date: to_string(bucket.bucket_start_date)
    }
    |> DistillProjectPeriodSummary.new()
    |> Oban.insert()

    %{project_id: session.project_id}
    |> DistillProjectRollingSummary.new()
    |> Oban.insert()
  end

  defp load_session(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %Session{} = session} -> session
      _ -> nil
    end
  end

  defp has_commit_links?(session) do
    SessionCommitLink
    |> Ash.Query.filter(session_id == ^session.id)
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> Enum.any?()
  end
end
