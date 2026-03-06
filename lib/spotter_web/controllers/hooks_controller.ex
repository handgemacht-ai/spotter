defmodule SpotterWeb.HooksController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Spotter.Observability.ErrorReport
  alias Spotter.Observability.FlowHub
  alias Spotter.Observability.FlowKeys
  alias Spotter.Services.InstructionsLoadedExtractor
  alias Spotter.Services.SessionEndFinalizer
  alias Spotter.Services.ShellCommandExtractor
  alias Spotter.Services.SubagentLifecycleIngestor
  alias Spotter.Telemetry.TraceContext
  alias Spotter.Transcripts.Commit
  alias Spotter.Transcripts.FileSnapshot
  alias Spotter.Transcripts.Jobs.ComputeCoChange
  alias Spotter.Transcripts.Jobs.ComputeHeatmap
  alias Spotter.Transcripts.Jobs.EnrichCommits
  alias Spotter.Transcripts.RawHookEvent
  alias Spotter.Transcripts.Session
  alias Spotter.Transcripts.SessionCommitLink
  alias Spotter.Transcripts.Sessions
  alias Spotter.Transcripts.ToolCall
  alias SpotterWeb.OtelTraceHelpers

  require Ash.Query
  require Logger
  require SpotterWeb.OtelTraceHelpers

  @max_commit_hashes 50
  @hash_pattern ~r/\A[0-9a-fA-F]{40}\z/
  @max_field_size 10_240
  @preserved_keys ~w(session_id tool_use_id file_path transcript_path cwd hook_event_name tool_name error agent_id agent_type)
  @max_truncation_depth 10

  def commit_event(conn, %{"session_id" => session_id, "new_commit_hashes" => hashes} = params)
      when is_binary(session_id) and is_list(hashes) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "PostToolUse"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"

    flow_keys =
      [FlowKeys.session(session_id)] ++ Enum.map(hashes, &FlowKeys.commit/1)

    OtelTraceHelpers.with_span "spotter.hook.commit_event", %{
      "spotter.session_id" => session_id,
      "spotter.hash_count" => length(hashes),
      "spotter.hook.event" => hook_event,
      "spotter.hook.script" => hook_script
    } do
      emit_hook_received("commit_event", flow_keys, %{
        "session_id" => session_id,
        "hash_count" => length(hashes),
        "hook_event" => hook_event,
        "hook_script" => hook_script
      })

      with :ok <- validate_hashes(hashes),
           {:ok, session} <- find_session(session_id) do
        evidence = build_evidence(params)
        ingested = ingest_commits(hashes, session, params["git_branch"], evidence)
        enqueue_enrichment(hashes, session)
        enqueue_heatmap(session)

        emit_hook_outcome("commit_event", :ok, flow_keys)

        conn
        |> put_status(:created)
        |> OtelTraceHelpers.put_trace_response_header()
        |> json(%{ok: true, ingested: ingested})
      else
        {:error, :too_many} ->
          error_payload =
            ErrorReport.hook_flow_error(
              "too_many_hashes",
              "too many commit hashes (max 50)",
              400,
              hook_event,
              hook_script,
              %{"hash_count" => length(hashes), "max_hashes" => @max_commit_hashes}
            )

          OtelTraceHelpers.set_error("too_many_hashes", %{
            "http.status_code" => 400,
            "error.source" => "hooks_controller"
          })

          emit_hook_outcome("commit_event", :error, flow_keys, error_payload)

          conn
          |> put_status(:bad_request)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "too many commit hashes (max 50)"})

        {:error, :invalid_format} ->
          invalid_hashes =
            hashes
            |> Enum.reject(&Regex.match?(@hash_pattern, &1))
            |> Enum.take(10)

          error_payload =
            ErrorReport.hook_flow_error(
              "invalid_format",
              "invalid commit hash format",
              400,
              hook_event,
              hook_script,
              %{
                "hash_count" => length(hashes),
                "invalid_count" => length(invalid_hashes),
                "invalid_hashes" => invalid_hashes
              }
            )

          OtelTraceHelpers.set_error("invalid_format", %{
            "http.status_code" => 400,
            "error.source" => "hooks_controller"
          })

          emit_hook_outcome("commit_event", :error, flow_keys, error_payload)

          conn
          |> put_status(:bad_request)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "invalid commit hash format"})

        {:error, :session_not_found} ->
          error_payload =
            ErrorReport.hook_flow_error(
              "session_not_found",
              "session not found",
              404,
              hook_event,
              hook_script,
              %{"session_id" => session_id}
            )

          OtelTraceHelpers.set_error("session_not_found", %{
            "http.status_code" => 404,
            "error.source" => "hooks_controller"
          })

          emit_hook_outcome("commit_event", :error, flow_keys, error_payload)

          conn
          |> put_status(:not_found)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "session not found"})
      end
    end
  end

  def commit_event(conn, _params) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "PostToolUse"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"

    OtelTraceHelpers.with_span "spotter.hook.commit_event", %{} do
      error_payload =
        ErrorReport.hook_flow_error(
          "invalid_params",
          "session_id and new_commit_hashes required",
          400,
          hook_event,
          hook_script,
          %{"reason" => "session_id and new_commit_hashes required"}
        )

      OtelTraceHelpers.set_error("invalid_params", %{
        "http.status_code" => 400,
        "error.source" => "hooks_controller"
      })

      emit_hook_outcome("commit_event", :error, [FlowKeys.system()], error_payload)

      conn
      |> put_status(:bad_request)
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{error: "session_id and new_commit_hashes required"})
    end
  end

  def file_snapshot(conn, %{"session_id" => session_id} = params)
      when is_binary(session_id) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "PostToolUse"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"
    flow_keys = [FlowKeys.session(session_id)]

    OtelTraceHelpers.with_span "spotter.hook.file_snapshot", %{
      "spotter.session_id" => session_id,
      "spotter.tool_use_id" => params["tool_use_id"] || "unknown",
      "spotter.hook.event" => hook_event,
      "spotter.hook.script" => hook_script
    } do
      emit_hook_received("file_snapshot", flow_keys, %{
        "session_id" => session_id,
        "tool_use_id" => params["tool_use_id"],
        "hook_event" => hook_event,
        "hook_script" => hook_script
      })

      with {:ok, session} <- find_session(session_id),
           {:ok, attrs} <- build_attrs(params, session),
           {:ok, _snapshot} <- Ash.create(FileSnapshot, attrs) do
        maybe_update_line_stats(session, attrs)
        enqueue_heatmap(session)
        emit_hook_outcome("file_snapshot", :ok, flow_keys)

        conn
        |> put_status(:created)
        |> OtelTraceHelpers.put_trace_response_header()
        |> json(%{ok: true})
      else
        {:error, :session_not_found} ->
          error_payload =
            ErrorReport.hook_flow_error(
              "session_not_found",
              "session not found",
              404,
              hook_event,
              hook_script,
              %{"session_id" => session_id}
            )

          OtelTraceHelpers.set_error("session_not_found", %{
            "http.status_code" => 404,
            "error.source" => "hooks_controller"
          })

          emit_hook_outcome("file_snapshot", :error, flow_keys, error_payload)

          conn
          |> put_status(:not_found)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "session not found"})

        {:error, :invalid_params, reason} ->
          error_payload =
            ErrorReport.hook_flow_error(
              "invalid_params",
              reason,
              400,
              hook_event,
              hook_script,
              %{"reason" => reason}
            )

          OtelTraceHelpers.set_error("invalid_params", %{
            "http.status_code" => 400,
            "error.details" => reason,
            "error.source" => "hooks_controller"
          })

          emit_hook_outcome("file_snapshot", :error, flow_keys, error_payload)

          conn
          |> put_status(:bad_request)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: reason})

        {:error, changeset} ->
          error_payload =
            ErrorReport.hook_flow_error(
              "validation_error",
              inspect(changeset),
              422,
              hook_event,
              hook_script
            )

          OtelTraceHelpers.set_error("validation_error", %{
            "http.status_code" => 422,
            "error.source" => "hooks_controller"
          })

          emit_hook_outcome("file_snapshot", :error, flow_keys, error_payload)

          conn
          |> put_status(:unprocessable_entity)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: inspect(changeset)})
      end
    end
  end

  def file_snapshot(conn, _params) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "PostToolUse"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"

    OtelTraceHelpers.with_span "spotter.hook.file_snapshot", %{} do
      error_payload =
        ErrorReport.hook_flow_error(
          "invalid_params",
          "session_id is required",
          400,
          hook_event,
          hook_script,
          %{"reason" => "session_id is required"}
        )

      OtelTraceHelpers.set_error("invalid_params", %{
        "http.status_code" => 400,
        "error.source" => "hooks_controller"
      })

      emit_hook_outcome("file_snapshot", :error, [FlowKeys.system()], error_payload)

      conn
      |> put_status(:bad_request)
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{error: "session_id is required"})
    end
  end

  def raw_event(conn, %{"hook_payload" => hook_payload, "env" => env} = params)
      when is_map(hook_payload) and is_map(env) do
    meta = raw_event_meta(conn, hook_payload)

    OtelTraceHelpers.with_span "spotter.hook.raw_event", meta.span_attrs do
      emit_hook_received("raw_event", meta.flow_keys, meta.received_payload)

      handle_raw_event_result(
        conn,
        meta,
        hook_payload,
        persist_raw_event(hook_payload, env, params["captured_at"])
      )
    end
  end

  def raw_event(conn, _params) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "unknown"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"

    OtelTraceHelpers.with_span "spotter.hook.raw_event", %{} do
      error_payload =
        ErrorReport.hook_flow_error(
          "invalid_params",
          "hook_payload and env are required",
          400,
          hook_event,
          hook_script,
          %{"reason" => "hook_payload and env are required"}
        )

      OtelTraceHelpers.set_error("invalid_params", %{
        "http.status_code" => 400,
        "error.source" => "hooks_controller"
      })

      emit_hook_outcome("raw_event", :error, [FlowKeys.system()], error_payload)

      conn
      |> put_status(:bad_request)
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{error: "hook_payload and env are required"})
    end
  end

  def tool_call(conn, %{"session_id" => session_id} = params)
      when is_binary(session_id) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "PostToolUse"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"
    flow_keys = [FlowKeys.session(session_id)]

    OtelTraceHelpers.with_span "spotter.hook.tool_call", %{
      "spotter.session_id" => session_id,
      "spotter.tool_use_id" => params["tool_use_id"] || "unknown",
      "spotter.tool_name" => params["tool_name"] || "unknown",
      "spotter.hook.event" => hook_event,
      "spotter.hook.script" => hook_script
    } do
      emit_hook_received("tool_call", flow_keys, %{
        "session_id" => session_id,
        "tool_use_id" => params["tool_use_id"],
        "tool_name" => params["tool_name"],
        "hook_event" => hook_event,
        "hook_script" => hook_script
      })

      with {:ok, session} <- Sessions.find_or_create(session_id),
           {:ok, _tool_call} <- create_tool_call(session, params) do
        emit_hook_outcome("tool_call", :ok, flow_keys)

        conn
        |> put_status(:created)
        |> OtelTraceHelpers.put_trace_response_header()
        |> json(%{ok: true})
      else
        {:error, :validation_error, changeset} ->
          error_payload =
            ErrorReport.hook_flow_error(
              "validation_error",
              inspect(changeset),
              422,
              hook_event,
              hook_script
            )

          OtelTraceHelpers.set_error("validation_error", %{
            "http.status_code" => 422,
            "error.source" => "hooks_controller"
          })

          emit_hook_outcome("tool_call", :error, flow_keys, error_payload)

          conn
          |> put_status(:unprocessable_entity)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: inspect(changeset)})

        {:error, reason} ->
          error_payload =
            ErrorReport.hook_flow_error(
              "session_creation_error",
              inspect(reason),
              422,
              hook_event,
              hook_script
            )

          OtelTraceHelpers.set_error("session_creation_error", %{
            "http.status_code" => 422,
            "error.source" => "hooks_controller"
          })

          emit_hook_outcome("tool_call", :error, flow_keys, error_payload)

          conn
          |> put_status(:unprocessable_entity)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: inspect(reason)})
      end
    end
  end

  def tool_call(conn, _params) do
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "PostToolUse"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"

    OtelTraceHelpers.with_span "spotter.hook.tool_call", %{} do
      error_payload =
        ErrorReport.hook_flow_error(
          "invalid_params",
          "session_id is required",
          400,
          hook_event,
          hook_script,
          %{"reason" => "session_id is required"}
        )

      OtelTraceHelpers.set_error("invalid_params", %{
        "http.status_code" => 400,
        "error.source" => "hooks_controller"
      })

      emit_hook_outcome("tool_call", :error, [FlowKeys.system()], error_payload)

      conn
      |> put_status(:bad_request)
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{error: "session_id is required"})
    end
  end

  defp maybe_update_line_stats(session, %{source: source} = attrs)
       when source in [:write, :edit] do
    before_lines = count_lines(attrs[:content_before])
    after_lines = count_lines(attrs[:content_after])
    added_delta = max(after_lines - before_lines, 0)
    removed_delta = max(before_lines - after_lines, 0)

    OpenTelemetry.Tracer.set_attribute("spotter.file_snapshot.before_lines", before_lines)
    OpenTelemetry.Tracer.set_attribute("spotter.file_snapshot.after_lines", after_lines)
    OpenTelemetry.Tracer.set_attribute("spotter.file_snapshot.lines_added_delta", added_delta)
    OpenTelemetry.Tracer.set_attribute("spotter.file_snapshot.lines_removed_delta", removed_delta)

    if added_delta > 0 or removed_delta > 0 do
      Ash.update(session, %{added_delta: added_delta, removed_delta: removed_delta},
        action: :add_line_stats
      )
    else
      :ok
    end
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp maybe_update_line_stats(_session, _attrs), do: :ok

  defp count_lines(nil), do: 0
  defp count_lines(""), do: 0

  defp count_lines(content) when is_binary(content) do
    newlines = content |> :binary.matches("\n") |> length()

    if String.ends_with?(content, "\n") do
      newlines
    else
      newlines + 1
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
          "unknown"
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

  defp insert_and_emit(args, worker_module, flow_payload) do
    args = OtelTraceHelpers.maybe_add_trace_context(args)
    changeset = worker_module.new(args)

    case Oban.insert(changeset) do
      {:ok, job} ->
        flow_keys =
          [FlowKeys.oban(to_string(job.id))] ++ FlowKeys.derive(flow_payload)

        FlowHub.record(%{
          kind: "oban.enqueued",
          status: :queued,
          flow_keys: flow_keys,
          summary: "Enqueued #{inspect(worker_module)}",
          traceparent: TraceContext.current_traceparent(),
          payload:
            Map.merge(flow_payload, %{
              "job_id" => job.id,
              "worker" => inspect(worker_module),
              "queue" => to_string(job.queue)
            })
        })

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  # --- Enqueue helpers ---

  defp enqueue_heatmap(session) do
    insert_and_emit(%{project_id: session.project_id}, ComputeHeatmap, %{
      "project_id" => session.project_id
    })

    insert_and_emit(%{project_id: session.project_id}, ComputeCoChange, %{
      "project_id" => session.project_id
    })
  end

  defp enqueue_enrichment(hashes, session) when hashes != [] do
    args =
      %{
        commit_hashes: hashes,
        session_id: session.session_id,
        git_cwd: session.cwd || "."
      }
      |> OtelTraceHelpers.maybe_add_trace_context()

    insert_and_emit(args, EnrichCommits, %{
      "session_id" => session.session_id,
      "commit_hashes" => hashes
    })
  end

  defp enqueue_enrichment(_, _), do: :ok

  defp validate_hashes(hashes) do
    cond do
      length(hashes) > @max_commit_hashes -> {:error, :too_many}
      not Enum.all?(hashes, &Regex.match?(@hash_pattern, &1)) -> {:error, :invalid_format}
      true -> :ok
    end
  end

  defp build_evidence(params) do
    %{
      "tool_use_id" => params["tool_use_id"],
      "base_head" => params["base_head"],
      "head" => params["head"],
      "captured_at" => params["captured_at"],
      "source" => "hook-minimal"
    }
  end

  defp ingest_commits(hashes, session, git_branch, evidence) do
    Enum.count(hashes, fn hash ->
      with {:ok, commit} <- Ash.create(Commit, %{commit_hash: hash, git_branch: git_branch}),
           {:ok, _link} <-
             Ash.create(SessionCommitLink, %{
               session_id: session.id,
               commit_id: commit.id,
               link_type: :observed_in_session,
               confidence: 1.0,
               evidence: evidence
             }) do
        true
      else
        _ -> false
      end
    end)
  end

  defp find_session(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, nil} -> {:error, :session_not_found}
      {:ok, session} -> {:ok, session}
      {:error, _} -> {:error, :session_not_found}
    end
  end

  defp build_attrs(params, session) do
    with {:ok, change_type} <- to_existing_atom(params["change_type"], "change_type"),
         {:ok, source} <- to_existing_atom(params["source"], "source"),
         {:ok, timestamp} <- parse_timestamp(params["timestamp"]) do
      {relative_path, strategy} =
        derive_relative_path(params["relative_path"], params["file_path"], session.cwd)

      OpenTelemetry.Tracer.set_attribute(
        "spotter.file_snapshot.relative_path.strategy",
        strategy
      )

      {:ok,
       %{
         session_id: session.id,
         tool_use_id: params["tool_use_id"],
         file_path: params["file_path"],
         relative_path: relative_path,
         content_before: params["content_before"],
         content_after: params["content_after"],
         change_type: change_type,
         source: source,
         timestamp: timestamp
       }}
    end
  end

  defp derive_relative_path(relative_path, _file_path, _cwd) when is_binary(relative_path) do
    {relative_path, "param"}
  end

  defp derive_relative_path(nil, file_path, cwd) when is_binary(file_path) do
    if String.starts_with?(file_path, "/") do
      derive_from_cwd(file_path, cwd)
    else
      {file_path, "relative"}
    end
  end

  defp derive_relative_path(nil, _file_path, _cwd), do: {nil, "none"}

  defp derive_from_cwd(file_path, cwd) when is_binary(cwd) do
    prefix = String.trim_trailing(cwd, "/") <> "/"

    if String.starts_with?(file_path, prefix) do
      {Path.relative_to(file_path, cwd), "cwd_prefix"}
    else
      {nil, "none"}
    end
  end

  defp derive_from_cwd(_file_path, _cwd), do: {nil, "none"}

  defp to_existing_atom(value, field) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, :invalid_params, "invalid #{field}: #{value}"}
  end

  defp to_existing_atom(nil, field), do: {:error, :invalid_params, "#{field} is required"}

  defp parse_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:ok, DateTime.utc_now()}
    end
  end

  defp parse_timestamp(_), do: {:ok, DateTime.utc_now()}

  defp create_tool_call(session, params) do
    error_content =
      case params["error_content"] do
        nil -> nil
        content when is_binary(content) -> String.slice(content, 0, 1000)
        _ -> nil
      end

    attrs = %{
      session_id: session.id,
      tool_use_id: params["tool_use_id"],
      tool_name: params["tool_name"],
      is_error: params["is_error"] || false,
      error_content: error_content
    }

    case Ash.create(ToolCall, attrs, action: :upsert) do
      {:ok, _tool_call} -> {:ok, nil}
      {:error, changeset} -> {:error, :validation_error, changeset}
    end
  end

  # --- Raw event helpers ---

  defp raw_event_meta(conn, hook_payload) do
    session_id = hook_payload["session_id"]
    hook_event_name = hook_payload["hook_event_name"]
    tool_name = hook_payload["tool_name"]
    hook_event = get_req_header(conn, "x-spotter-hook-event") |> List.first() || "unknown"
    hook_script = get_req_header(conn, "x-spotter-hook-script") |> List.first() || "unknown"

    %{
      hook_event: hook_event,
      hook_script: hook_script,
      flow_keys: if(session_id, do: [FlowKeys.session(session_id)], else: [FlowKeys.system()]),
      span_attrs: %{
        "spotter.session_id" => session_id || "unknown",
        "spotter.hook_event_name" => hook_event_name || "unknown",
        "spotter.tool_name" => tool_name || "unknown",
        "spotter.hook.event" => hook_event,
        "spotter.hook.script" => hook_script
      },
      received_payload: %{
        "session_id" => session_id,
        "hook_event_name" => hook_event_name,
        "tool_name" => tool_name,
        "hook_event" => hook_event,
        "hook_script" => hook_script
      }
    }
  end

  defp handle_raw_event_result(conn, meta, hook_payload, {:ok, event}) do
    maybe_finalize_session_end(hook_payload)
    maybe_extract_shell_commands(hook_payload, event)
    maybe_extract_instructions_loaded(hook_payload, event)
    maybe_ingest_subagent_lifecycle(hook_payload, event)
    emit_hook_outcome("raw_event", :ok, meta.flow_keys)

    conn
    |> put_status(:created)
    |> OtelTraceHelpers.put_trace_response_header()
    |> json(%{ok: true})
  end

  defp handle_raw_event_result(conn, meta, _hook_payload, {:error, changeset}) do
    respond_raw_event_error(
      conn,
      meta,
      "validation_error",
      inspect(changeset),
      :unprocessable_entity,
      422
    )
  end

  defp respond_raw_event_error(conn, meta, error_type, message, http_status, status_code) do
    error_payload =
      ErrorReport.hook_flow_error(
        error_type,
        message,
        status_code,
        meta.hook_event,
        meta.hook_script,
        %{
          "reason" => message
        }
      )

    OtelTraceHelpers.set_error(error_type, %{
      "http.status_code" => status_code,
      "error.source" => "hooks_controller"
    })

    emit_hook_outcome("raw_event", :error, meta.flow_keys, error_payload)

    conn
    |> put_status(http_status)
    |> OtelTraceHelpers.put_trace_response_header()
    |> json(%{error: message})
  end

  defp maybe_extract_shell_commands(hook_payload, event) do
    OtelTraceHelpers.with_span "spotter.shell_telemetry.ingest", %{
      "spotter.session_id" => hook_payload["session_id"] || "unknown",
      "spotter.tool_use_id" => hook_payload["tool_use_id"] || "unknown",
      "spotter.hook.event" => hook_payload["hook_event_name"] || "unknown"
    } do
      case ShellCommandExtractor.extract_and_persist(hook_payload, to_string(event.id)) do
        {:ok, count, project_id} ->
          OpenTelemetry.Tracer.set_attribute("spotter.shell_command.count", count)

          if project_id do
            OpenTelemetry.Tracer.set_attribute("spotter.project_id", project_id)
            broadcast_shell_telemetry(project_id)
          end

        {:error, reason} ->
          OtelTraceHelpers.set_error("shell_telemetry_ingest_failed", %{
            "error.details" => inspect(reason)
          })
      end
    end
  rescue
    error ->
      Logger.warning("Shell command extraction failed: #{Exception.message(error)}")
      :ok
  end

  defp broadcast_shell_telemetry(project_id) do
    Phoenix.PubSub.broadcast(
      Spotter.PubSub,
      SpotterWeb.ShellTelemetryLive.telemetry_topic(project_id),
      {:shell_telemetry_updated, %{project_id: project_id}}
    )
  rescue
    error ->
      Logger.warning("Shell telemetry broadcast failed: #{Exception.message(error)}")
      :ok
  end

  defp maybe_extract_instructions_loaded(hook_payload, event) do
    OtelTraceHelpers.with_span "spotter.instructions_telemetry.ingest", %{
      "spotter.session_id" => hook_payload["session_id"] || "unknown",
      "spotter.hook.event" => hook_payload["hook_event_name"] || "unknown"
    } do
      case InstructionsLoadedExtractor.extract_and_persist(hook_payload, to_string(event.id)) do
        {:ok, project_id} when is_binary(project_id) ->
          OpenTelemetry.Tracer.set_attribute("spotter.project_id", project_id)

        {:ok, _} ->
          :ok

        {:error, reason} ->
          OtelTraceHelpers.set_error("instructions_telemetry_ingest_failed", %{
            "error.details" => inspect(reason)
          })
      end
    end
  rescue
    error ->
      Logger.warning("Instructions loaded extraction failed: #{Exception.message(error)}")
      :ok
  end

  defp maybe_ingest_subagent_lifecycle(hook_payload, event) do
    OtelTraceHelpers.with_span "spotter.subagent_lifecycle.ingest", %{
      "spotter.session_id" => hook_payload["session_id"] || "unknown",
      "spotter.agent_id" => hook_payload["agent_id"] || "unknown",
      "spotter.hook.event" => hook_payload["hook_event_name"] || "unknown"
    } do
      case SubagentLifecycleIngestor.ingest(hook_payload, event) do
        {:ok, %{status: status}} ->
          OpenTelemetry.Tracer.set_attribute(
            "spotter.subagent_lifecycle.status",
            to_string(status)
          )

        {:error, reason} ->
          OtelTraceHelpers.set_error("subagent_lifecycle_ingest_failed", %{
            "error.details" => inspect(reason)
          })
      end
    end
  rescue
    error ->
      Logger.warning("Subagent lifecycle ingest failed: #{Exception.message(error)}")
      :ok
  end

  defp maybe_finalize_session_end(
         %{"hook_event_name" => "SessionEnd", "session_id" => session_id} = payload
       )
       when is_binary(session_id) do
    trace_ctx = OtelTraceHelpers.maybe_add_trace_context(%{})
    SessionEndFinalizer.finalize(session_id, payload, trace_context: trace_ctx)
    :ok
  rescue
    error ->
      Logger.warning(
        "Failed to process SessionEnd raw event for #{session_id}: #{Exception.message(error)}"
      )

      :ok
  end

  defp maybe_finalize_session_end(_payload), do: :ok

  defp persist_raw_event(hook_payload, env, raw_captured_at) do
    session_id = hook_payload["session_id"]
    captured_at = parse_captured_at(raw_captured_at)

    effective_session_id =
      if is_nil(session_id) or session_id == "" do
        synthetic_session_id(hook_payload, captured_at)
      else
        session_id
      end

    is_synthetic = effective_session_id != session_id

    if is_synthetic do
      OpenTelemetry.Tracer.set_attribute("spotter.raw_event.synthetic_session_id", true)
    end

    attrs = %{
      session_id: effective_session_id,
      hook_event_name: hook_payload["hook_event_name"] || "unknown",
      tool_name: hook_payload["tool_name"],
      tool_use_id: hook_payload["tool_use_id"],
      hook_payload: truncate_large_strings(hook_payload, @max_field_size, 0),
      env: normalize_env(env),
      captured_at: captured_at
    }

    Ash.create(RawHookEvent, attrs, action: :upsert)
  end

  defp synthetic_session_id(hook_payload, captured_at) do
    hook_event = hook_payload["hook_event_name"] || "unknown"
    ts = DateTime.to_iso8601(captured_at)
    hash = :crypto.hash(:sha256, "#{hook_event}:#{ts}") |> Base.encode16(case: :lower)
    "synthetic-#{String.slice(hash, 0, 16)}"
  end

  defp parse_captured_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp parse_captured_at(_), do: DateTime.utc_now()

  defp truncate_large_strings(map, max_size, depth)
       when is_map(map) and depth < @max_truncation_depth do
    Map.new(map, fn {k, v} -> {k, truncate_field(k, v, max_size, depth)} end)
  end

  defp truncate_large_strings(value, _max_size, _depth), do: value

  defp truncate_field(key, value, _max_size, _depth) when key in @preserved_keys, do: value

  defp truncate_field(_key, value, max_size, _depth)
       when is_binary(value) and byte_size(value) > max_size do
    String.slice(value, 0, max_size) <> "[truncated]"
  end

  defp truncate_field(_key, value, max_size, depth) when is_map(value) do
    truncate_large_strings(value, max_size, depth + 1)
  end

  defp truncate_field(_key, value, max_size, depth) when is_list(value) do
    Enum.map(value, fn
      item when is_map(item) ->
        truncate_large_strings(item, max_size, depth + 1)

      item when is_binary(item) and byte_size(item) > max_size ->
        String.slice(item, 0, max_size) <> "[truncated]"

      item ->
        item
    end)
  end

  defp truncate_field(_key, value, _max_size, _depth), do: value

  defp normalize_env(env) when is_map(env) do
    Map.new(env, fn {k, v} -> {to_string(k), to_string(v)} end)
  end
end
