defmodule SpotterWeb.HooksController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Spotter.Observability.ErrorReport
  alias Spotter.Observability.FlowHub
  alias Spotter.Observability.FlowKeys
  alias Spotter.Telemetry.TraceContext
  alias Spotter.Transcripts.Commit
  alias Spotter.Transcripts.FileSnapshot
  alias Spotter.Transcripts.Jobs.ComputeCoChange
  alias Spotter.Transcripts.Jobs.ComputeHeatmap
  alias Spotter.Transcripts.Jobs.EnrichCommits
  alias Spotter.Transcripts.Session
  alias Spotter.Transcripts.SessionCommitLink
  alias Spotter.Transcripts.Sessions
  alias Spotter.Transcripts.ToolCall
  alias SpotterWeb.OtelTraceHelpers

  require Ash.Query
  require SpotterWeb.OtelTraceHelpers

  @max_commit_hashes 50
  @hash_pattern ~r/\A[0-9a-fA-F]{40}\z/

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
end
