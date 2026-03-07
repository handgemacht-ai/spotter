defmodule SpotterWeb.SessionHookController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Spotter.Config.Runtime
  alias Spotter.Observability.ErrorReport
  alias Spotter.Observability.FlowHub
  alias Spotter.Observability.FlowKeys
  alias Spotter.Services.SessionActivityBroadcaster
  alias Spotter.Services.SessionEndFinalizer
  alias Spotter.Services.TranscriptTailSupervisor
  alias Spotter.Telemetry.TraceContext
  alias Spotter.Transcripts.Jobs.{IngestRecentCommits, SyncTranscripts}
  alias Spotter.Transcripts.Sessions
  alias SpotterWeb.OtelTraceHelpers

  require Logger
  require SpotterWeb.OtelTraceHelpers

  def session_start(conn, %{"session_id" => session_id, "pane_id" => pane_id} = params)
      when is_binary(session_id) and is_binary(pane_id) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "SessionStart"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"
    flow_keys = [FlowKeys.session(session_id)]

    OtelTraceHelpers.with_span "spotter.hook.session_start", %{
      "spotter.session_id" => session_id,
      "spotter.pane_id" => pane_id,
      "spotter.hook.event" => hook_event,
      "spotter.hook.script" => hook_script
    } do
      emit_hook_received("session_start", flow_keys, %{
        "session_id" => session_id,
        "pane_id" => pane_id,
        "hook_event" => hook_event,
        "hook_script" => hook_script
      })

      case Sessions.find_or_create(session_id, cwd: params["cwd"]) do
        {:ok, session} ->
          maybe_bootstrap_sync(session, params["transcript_path"])
          enqueue_ingest(session.project_id)
          maybe_start_tail_worker(session_id, params["cwd"], params["transcript_path"])
          SessionActivityBroadcaster.broadcast_started(session_id)

        {:error, reason} ->
          Logger.warning("Failed to create session #{session_id}: #{inspect(reason)}")
      end

      emit_hook_outcome("session_start", :ok, flow_keys)

      conn
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{ok: true})
    end
  end

  def session_start(conn, _params) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "SessionStart"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"

    OtelTraceHelpers.with_span "spotter.hook.session_start", %{} do
      error_payload =
        ErrorReport.hook_flow_error(
          "invalid_params",
          "session_id and pane_id are required",
          400,
          hook_event,
          hook_script,
          %{
            "error.source" => "session_hook_controller",
            "reason" => "session_id and pane_id are required"
          }
        )

      OtelTraceHelpers.set_error("invalid_params", %{
        "http.status_code" => 400,
        "error.source" => "session_hook_controller"
      })

      emit_hook_outcome("session_start", :error, [FlowKeys.system()], error_payload)

      conn
      |> put_status(:bad_request)
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{error: "session_id and pane_id are required"})
    end
  end

  def waiting_summary(conn, %{"session_id" => session_id} = _params)
      when is_binary(session_id) do
    OtelTraceHelpers.with_span "spotter.hook.waiting_summary", %{
      "spotter.session_id" => session_id
    } do
      conn
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{
        ok: true,
        summary: "Session #{session_id} in progress.",
        input_chars: 0,
        source_window: %{head_messages: 0, tail_messages: 0}
      })
    end
  end

  def waiting_summary(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> OtelTraceHelpers.put_trace_response_header()
    |> json(%{error: "session_id is required"})
  end

  def session_end(conn, %{"session_id" => session_id} = params)
      when is_binary(session_id) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "SessionEnd"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"
    reason = params["reason"] || "unknown"
    flow_keys = [FlowKeys.session(session_id)]

    OtelTraceHelpers.with_span "spotter.hook.session_end", %{
      "spotter.session_id" => session_id,
      "spotter.hook.event" => hook_event,
      "spotter.hook.script" => hook_script,
      "spotter.session_end.reason" => reason
    } do
      emit_hook_received("session_end", flow_keys, %{
        "session_id" => session_id,
        "hook_event" => hook_event,
        "hook_script" => hook_script,
        "reason" => reason
      })

      trace_ctx = OtelTraceHelpers.maybe_add_trace_context(%{})
      finalize_opts = [trace_context: trace_ctx]

      finalize_opts =
        case params["transcript_path"] do
          path when is_binary(path) and path != "" ->
            [{:transcript_path, path} | finalize_opts]

          _ ->
            finalize_opts
        end

      result = SessionEndFinalizer.finalize(session_id, params, finalize_opts)

      OtelTraceHelpers.set_attributes_safely(%{
        "spotter.session_end.sync_status" => to_string(result.sync_status),
        "spotter.session_end.ingested_messages" => result.ingested_messages,
        "spotter.session_end.marked_ended" => to_string(result.marked_ended),
        "spotter.session_end.ingest_enqueued" => result.ingest_enqueued,
        "spotter.session_end.marked_finished" => result.marked_ended == :ok
      })

      emit_hook_outcome("session_end", :ok, flow_keys)

      conn
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{ok: true})
    end
  end

  def session_end(conn, _params) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "SessionEnd"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"

    OtelTraceHelpers.with_span "spotter.hook.session_end", %{} do
      error_payload =
        ErrorReport.hook_flow_error(
          "invalid_params",
          "session_id is required",
          400,
          hook_event,
          hook_script,
          %{
            "error.source" => "session_hook_controller",
            "reason" => "session_id is required"
          }
        )

      OtelTraceHelpers.set_error("invalid_params", %{
        "http.status_code" => 400,
        "error.source" => "session_hook_controller"
      })

      emit_hook_outcome("session_end", :error, [FlowKeys.system()], error_payload)

      conn
      |> put_status(:bad_request)
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{error: "session_id is required"})
    end
  end

  # --- Flow event helpers ---

  defp emit_hook_received(hook_name, flow_keys, payload) do
    FlowHub.record(%{
      kind: "hook.#{hook_name}.received",
      status: :running,
      flow_keys: flow_keys,
      summary: "Hook #{hook_name} received",
      traceparent: TraceContext.current_traceparent(),
      payload: payload
    })
  rescue
    _ -> :ok
  end

  defp emit_hook_outcome(hook_name, status, flow_keys, payload \\ %{}) do
    payload =
      if status == :error and payload == %{} do
        ErrorReport.hook_flow_error(
          "unknown",
          "hook outcome error",
          500,
          "unknown",
          "unknown",
          %{"error.source" => "session_hook_controller"}
        )
      else
        payload
      end

    FlowHub.record(%{
      kind: "hook.#{hook_name}.#{status}",
      status: status,
      flow_keys: flow_keys,
      summary: "Hook #{hook_name} #{status}",
      traceparent: TraceContext.current_traceparent(),
      payload: payload
    })
  rescue
    _ -> :ok
  end

  # --- Private helpers ---

  defp enqueue_ingest(project_id) do
    %{project_id: project_id}
    |> OtelTraceHelpers.maybe_add_trace_context()
    |> IngestRecentCommits.new()
    |> Oban.insert()
  end

  defp maybe_start_tail_worker(session_id, _cwd, transcript_path)
       when is_binary(transcript_path) and transcript_path != "" do
    start_tail_worker(session_id, transcript_path)
  end

  defp maybe_start_tail_worker(session_id, cwd, _transcript_path) when is_binary(cwd) do
    start_tail_worker(session_id, live_transcript_path(cwd, session_id))
  end

  defp maybe_start_tail_worker(_session_id, _cwd, _transcript_path), do: :ok

  defp start_tail_worker(session_id, path) do
    TranscriptTailSupervisor.ensure_worker(session_id, path)
  rescue
    error ->
      Logger.debug("Failed to start tail worker for #{session_id}: #{inspect(error)}")
      :ok
  end

  defp live_transcript_path(cwd, session_id) do
    {candidate_roots, _source} = Runtime.transcript_roots()
    dir_name = String.replace(cwd, "/", "-")
    fallback_root = List.first(candidate_roots)

    transcript_root =
      Enum.find(candidate_roots, &File.dir?(Path.join(&1, dir_name))) || fallback_root

    Path.join([transcript_root, dir_name, "#{session_id}.jsonl"])
  end

  @env Application.compile_env(:spotter, :env, :prod)

  defp maybe_bootstrap_sync(session, transcript_path) do
    cond do
      @env == :test ->
        :ok

      is_nil(session.message_count) or session.message_count == 0 ->
        trace_ctx = OtelTraceHelpers.maybe_add_trace_context(%{})
        session_id = session.session_id

        sync_opts = [trace_context: trace_ctx]

        sync_opts =
          if is_binary(transcript_path) and transcript_path != "",
            do: [{:transcript_path, transcript_path} | sync_opts],
            else: sync_opts

        Task.start(fn ->
          SyncTranscripts.sync_session_by_id(session_id, sync_opts)
        end)

      true ->
        :ok
    end
  rescue
    error ->
      OtelTraceHelpers.set_error("bootstrap_sync_failed", %{
        "error.message" => Exception.message(error),
        "error.source" => "session_hook_controller"
      })

      :ok
  end
end
