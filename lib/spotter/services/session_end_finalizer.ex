defmodule Spotter.Services.SessionEndFinalizer do
  @moduledoc false

  alias Spotter.Services.SessionActivityBroadcaster
  alias Spotter.Services.TranscriptTailSupervisor
  alias Spotter.Transcripts.Jobs.{IngestRecentCommits, SyncTranscripts}
  alias Spotter.Transcripts.{Session, Sessions}

  require Ash.Query
  require Logger

  @spec finalize(String.t(), map(), keyword()) :: %{
          sync_status: atom(),
          ingested_messages: non_neg_integer(),
          marked_ended: :ok | :error,
          ingest_enqueued: boolean()
        }
  def finalize(session_id, params \\ %{}, opts \\ []) when is_binary(session_id) do
    trace_context = normalize_trace_context(Keyword.get(opts, :trace_context, %{}))

    transcript_path = Keyword.get(opts, :transcript_path)

    stop_worker(session_id)

    sync_opts = [trace_context: trace_context]

    sync_opts =
      if is_binary(transcript_path) and transcript_path != "",
        do: [{:transcript_path, transcript_path} | sync_opts],
        else: sync_opts

    sync_result =
      SyncTranscripts.sync_session_by_id(session_id, sync_opts)

    mark_result = mark_ended(session_id, params)
    if mark_result == :ok, do: SessionActivityBroadcaster.broadcast_finished(session_id)
    ingest_enqueued = maybe_enqueue_ingest_for_session(session_id, trace_context)

    %{
      sync_status: sync_result[:status] || :error,
      ingested_messages: sync_result[:ingested_messages] || 0,
      marked_ended: mark_result,
      ingest_enqueued: ingest_enqueued
    }
  rescue
    error ->
      Logger.warning("Failed to finalize session #{session_id}: #{Exception.message(error)}")

      %{
        sync_status: :error,
        ingested_messages: 0,
        marked_ended: :error,
        ingest_enqueued: false
      }
  end

  defp stop_worker(session_id) do
    TranscriptTailSupervisor.stop_worker(session_id)
  rescue
    _ -> :ok
  end

  defp mark_ended(session_id, params) do
    cwd = map_value(params, "cwd")

    with {:ok, session} <- fetch_or_create_session(session_id, cwd),
         {:ok, _updated} <- Ash.update(session, %{session_ended_at: DateTime.utc_now()}) do
      :ok
    else
      {:error, :session_not_found} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to mark session ended #{session_id}: #{inspect(reason)}")
        :error
    end
  rescue
    error ->
      Logger.warning("Failed to mark session ended #{session_id}: #{Exception.message(error)}")
      :error
  end

  defp fetch_or_create_session(session_id, cwd) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %Session{} = session} ->
        {:ok, session}

      {:ok, nil} when is_binary(cwd) and cwd != "" ->
        Sessions.find_or_create(session_id, cwd: cwd)

      {:ok, nil} ->
        {:error, :session_not_found}

      {:error, _} = error ->
        error
    end
  end

  defp maybe_enqueue_ingest_for_session(session_id, trace_context) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %{project_id: project_id}} when is_binary(project_id) ->
        %{project_id: project_id}
        |> Map.merge(trace_context)
        |> IngestRecentCommits.new()
        |> Oban.insert()

        true

      _ ->
        false
    end
  rescue
    error ->
      Logger.debug(
        "Failed to enqueue ingest for session #{session_id}: #{Exception.message(error)}"
      )

      false
  end

  defp map_value(map, key) when is_map(map) and is_binary(key) do
    case key do
      "cwd" -> Map.get(map, "cwd") || Map.get(map, :cwd)
      _ -> Map.get(map, key)
    end
  end

  defp map_value(_map, _key), do: nil

  defp normalize_trace_context(context) when is_map(context), do: context
  defp normalize_trace_context(_), do: %{}
end
