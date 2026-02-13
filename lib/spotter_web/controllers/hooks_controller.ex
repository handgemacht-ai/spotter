defmodule SpotterWeb.HooksController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Spotter.ProductSpec.Jobs.UpdateRollingSpec
  alias Spotter.Services.ActiveSessionRegistry
  alias Spotter.Transcripts.Commit
  alias Spotter.Transcripts.FileSnapshot
  alias Spotter.Transcripts.Jobs.AnalyzeCommitHotspots
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

    OtelTraceHelpers.with_span "spotter.hook.commit_event", %{
      "spotter.session_id" => session_id,
      "spotter.hash_count" => length(hashes),
      "spotter.hook.event" => hook_event,
      "spotter.hook.script" => hook_script
    } do
      ActiveSessionRegistry.touch(session_id, :commit_event)

      with :ok <- validate_hashes(hashes),
           {:ok, session} <- find_session(session_id) do
        evidence = build_evidence(params)
        ingested = ingest_commits(hashes, session, params["git_branch"], evidence)
        enqueue_enrichment(hashes, session)
        enqueue_heatmap(session)
        enqueue_analyze_hotspots(hashes, session)
        enqueue_rolling_spec(hashes, session)

        conn
        |> put_status(:created)
        |> OtelTraceHelpers.put_trace_response_header()
        |> json(%{ok: true, ingested: ingested})
      else
        {:error, :too_many} ->
          OtelTraceHelpers.set_error("too_many_hashes", %{"http.status_code" => 400})

          conn
          |> put_status(:bad_request)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "too many commit hashes (max 50)"})

        {:error, :invalid_format} ->
          OtelTraceHelpers.set_error("invalid_format", %{"http.status_code" => 400})

          conn
          |> put_status(:bad_request)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "invalid commit hash format"})

        {:error, :session_not_found} ->
          OtelTraceHelpers.set_error("session_not_found", %{"http.status_code" => 404})

          conn
          |> put_status(:not_found)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "session not found"})
      end
    end
  end

  def commit_event(conn, _params) do
    OtelTraceHelpers.with_span "spotter.hook.commit_event", %{} do
      OtelTraceHelpers.set_error("invalid_params", %{"http.status_code" => 400})

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

    OtelTraceHelpers.with_span "spotter.hook.file_snapshot", %{
      "spotter.session_id" => session_id,
      "spotter.tool_use_id" => params["tool_use_id"] || "unknown",
      "spotter.hook.event" => hook_event,
      "spotter.hook.script" => hook_script
    } do
      ActiveSessionRegistry.touch(session_id, :file_snapshot)

      with {:ok, session} <- find_session(session_id),
           {:ok, attrs} <- build_attrs(params, session),
           {:ok, _snapshot} <- Ash.create(FileSnapshot, attrs) do
        enqueue_heatmap(session)

        conn
        |> put_status(:created)
        |> OtelTraceHelpers.put_trace_response_header()
        |> json(%{ok: true})
      else
        {:error, :session_not_found} ->
          OtelTraceHelpers.set_error("session_not_found", %{"http.status_code" => 404})

          conn
          |> put_status(:not_found)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "session not found"})

        {:error, :invalid_params, reason} ->
          OtelTraceHelpers.set_error("invalid_params", %{
            "http.status_code" => 400,
            "error.details" => reason
          })

          conn
          |> put_status(:bad_request)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: reason})

        {:error, changeset} ->
          OtelTraceHelpers.set_error("validation_error", %{"http.status_code" => 422})

          conn
          |> put_status(:unprocessable_entity)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: inspect(changeset)})
      end
    end
  end

  def file_snapshot(conn, _params) do
    OtelTraceHelpers.with_span "spotter.hook.file_snapshot", %{} do
      OtelTraceHelpers.set_error("invalid_params", %{"http.status_code" => 400})

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

    OtelTraceHelpers.with_span "spotter.hook.tool_call", %{
      "spotter.session_id" => session_id,
      "spotter.tool_use_id" => params["tool_use_id"] || "unknown",
      "spotter.tool_name" => params["tool_name"] || "unknown",
      "spotter.hook.event" => hook_event,
      "spotter.hook.script" => hook_script
    } do
      ActiveSessionRegistry.touch(session_id, :tool_call)

      with {:ok, session} <- Sessions.find_or_create(session_id),
           {:ok, _tool_call} <- create_tool_call(session, params) do
        conn
        |> put_status(:created)
        |> OtelTraceHelpers.put_trace_response_header()
        |> json(%{ok: true})
      else
        {:error, :validation_error, changeset} ->
          OtelTraceHelpers.set_error("validation_error", %{"http.status_code" => 422})

          conn
          |> put_status(:unprocessable_entity)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: inspect(changeset)})

        {:error, reason} ->
          OtelTraceHelpers.set_error("session_creation_error", %{"http.status_code" => 422})

          conn
          |> put_status(:unprocessable_entity)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: inspect(reason)})
      end
    end
  end

  def tool_call(conn, _params) do
    OtelTraceHelpers.with_span "spotter.hook.tool_call", %{} do
      OtelTraceHelpers.set_error("invalid_params", %{"http.status_code" => 400})

      conn
      |> put_status(:bad_request)
      |> OtelTraceHelpers.put_trace_response_header()
      |> json(%{error: "session_id is required"})
    end
  end

  defp enqueue_heatmap(session) do
    %{project_id: session.project_id}
    |> ComputeHeatmap.new()
    |> Oban.insert()

    %{project_id: session.project_id}
    |> ComputeCoChange.new()
    |> Oban.insert()
  end

  defp enqueue_analyze_hotspots(hashes, session) when hashes != [] do
    Enum.each(hashes, fn hash ->
      %{project_id: session.project_id, commit_hash: hash}
      |> AnalyzeCommitHotspots.new()
      |> Oban.insert()
    end)
  end

  defp enqueue_analyze_hotspots(_, _), do: :ok

  defp enqueue_rolling_spec(hashes, session) when hashes != [] do
    if Spotter.ProductSpec.enabled?() do
      Enum.each(hashes, fn hash ->
        args =
          %{project_id: session.project_id, commit_hash: hash, git_cwd: session.cwd || "."}
          |> maybe_add_trace_id()

        args |> UpdateRollingSpec.new() |> Oban.insert()
      end)
    end
  end

  defp enqueue_rolling_spec(_, _), do: :ok

  defp enqueue_enrichment(hashes, session) when hashes != [] do
    args =
      %{
        commit_hashes: hashes,
        session_id: session.session_id,
        git_cwd: session.cwd || "."
      }
      |> maybe_add_trace_id()

    args
    |> EnrichCommits.new()
    |> Oban.insert()
  end

  defp enqueue_enrichment(_, _), do: :ok

  defp maybe_add_trace_id(args) do
    case OtelTraceHelpers.current_trace_id() do
      nil -> args
      trace_id -> Map.put(args, :otel_trace_id, trace_id)
    end
  end

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
