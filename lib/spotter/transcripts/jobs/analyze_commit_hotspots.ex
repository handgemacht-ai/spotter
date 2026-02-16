defmodule Spotter.Transcripts.Jobs.AnalyzeCommitHotspots do
  @moduledoc "Oban worker that analyzes a commit's diff and persists hotspots + review items."

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id, :commit_hash], period: 3600]

  require Ash.Query
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Search.Jobs.ReindexProject

  alias Spotter.Services.{
    CommitDiffExtractor,
    CommitHotspotAgent,
    CommitHotspotFilters,
    CommitPatchExtractor
  }

  alias Spotter.Transcripts.{Commit, CommitHotspot, ReviewItem, Session}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(6)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "commit_hash" => commit_hash}}) do
    Tracer.with_span "spotter.commit_hotspots.analyze.perform" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.commit_hash", commit_hash)

      case {load_commit(commit_hash), resolve_repo_path(project_id)} do
        {{:ok, commit}, {:ok, repo_path}} ->
          safe_run_analysis(project_id, commit, repo_path)

        {{:error, reason}, _} ->
          Logger.warning("AnalyzeCommitHotspots: commit not found: #{inspect(reason)}")
          :ok

        {_, :no_cwd} ->
          failure =
            build_failure("no_repo_path", "resolve_repo", message: "no accessible repo path")

          set_failure_trace_attributes(failure)
          mark_error(commit_hash, "no accessible repo path", failure)
          :ok
      end
    end
  end

  defp load_commit(commit_hash) do
    case Commit |> Ash.Query.filter(commit_hash == ^commit_hash) |> Ash.read_one() do
      {:ok, nil} -> {:error, :not_found}
      {:ok, commit} -> {:ok, commit}
      {:error, _} = err -> err
    end
  end

  defp resolve_repo_path(project_id) do
    case Session
         |> Ash.Query.filter(project_id == ^project_id and not is_nil(cwd))
         |> Ash.Query.sort(started_at: :desc)
         |> Ash.Query.limit(1)
         |> Ash.read!() do
      [session] -> if File.dir?(session.cwd), do: {:ok, session.cwd}, else: :no_cwd
      [] -> :no_cwd
    end
  end

  defp safe_run_analysis(project_id, commit, repo_path) do
    run_analysis(project_id, commit, repo_path)
  rescue
    e ->
      reason = Exception.message(e)
      Logger.warning("AnalyzeCommitHotspots: unexpected error: #{reason}")

      failure =
        build_failure("agent_error", "run_analysis",
          retryable: false,
          error_class: inspect(e.__struct__),
          message: reason
        )

      set_failure_trace_attributes(failure)
      Tracer.set_status(:error, reason)
      mark_error(commit.commit_hash, reason, failure)
      :ok
  catch
    :exit, exit_reason ->
      msg = inspect(exit_reason)
      Logger.warning("AnalyzeCommitHotspots: process exited: #{msg}")

      failure =
        build_failure("agent_exit", "run_analysis",
          retryable: true,
          message: msg
        )

      set_failure_trace_attributes(failure)
      Tracer.set_status(:error, msg)
      mark_error(commit.commit_hash, msg, failure)
      :ok
  end

  defp run_analysis(project_id, commit, repo_path) do
    started_at = DateTime.utc_now() |> DateTime.to_iso8601()

    with {:ok, diff_context} <- extract_diff_context(repo_path, commit.commit_hash),
         {:ok, result} <-
           CommitHotspotAgent.run(%{
             project_id: project_id,
             commit_hash: commit.commit_hash,
             commit_subject: commit.subject || "",
             diff_stats: diff_context.diff_stats,
             patch_files: diff_context.patch_files,
             git_cwd: repo_path
           }) do
      metadata =
        Map.merge(result.metadata, %{
          strategy: "tool_loop_v1",
          eligible_files: length(diff_context.patch_files),
          started_at: started_at
        })

      persist_hotspots(project_id, commit, %{result | metadata: metadata})
      mark_success(commit, metadata)
      %{project_id: project_id} |> ReindexProject.new() |> Oban.insert()
    else
      {:error, :missing_api_key} ->
        Logger.warning("AnalyzeCommitHotspots: missing API key, skipping")

        failure =
          build_failure("missing_api_key", "credentials",
            retryable: false,
            message: "missing_api_key"
          )

        set_failure_trace_attributes(failure)
        mark_error(commit.commit_hash, "missing_api_key", failure)
        :ok

      {:error, :no_structured_output} ->
        Logger.warning("AnalyzeCommitHotspots: no structured output from agent")

        failure =
          build_failure("no_structured_output", "agent_result",
            retryable: true,
            message: "agent did not return structured output"
          )

        set_failure_trace_attributes(failure)
        mark_error(commit.commit_hash, "no_structured_output", failure)
        :ok

      {:error, :invalid_main_response} ->
        Logger.warning("AnalyzeCommitHotspots: invalid structured output shape")

        failure =
          build_failure("invalid_structured_output", "agent_result",
            retryable: true,
            message: "structured output did not match expected schema"
          )

        set_failure_trace_attributes(failure)
        mark_error(commit.commit_hash, "invalid_structured_output", failure)
        :ok

      {:error, {:agent_error, reason}} ->
        Logger.warning("AnalyzeCommitHotspots: agent error: #{inspect(reason)}")

        failure =
          build_failure("agent_error", "agent_run",
            retryable: true,
            message: inspect(reason)
          )

        set_failure_trace_attributes(failure)
        mark_error(commit.commit_hash, inspect(reason), failure)
        :ok

      {:error, {:agent_exit, _} = reason} ->
        Logger.warning("AnalyzeCommitHotspots: agent exit: #{inspect(reason)}")

        failure =
          build_failure("agent_exit", "agent_run",
            retryable: true,
            message: inspect(reason)
          )

        set_failure_trace_attributes(failure)
        mark_error(commit.commit_hash, inspect(reason), failure)
        :ok

      {:error, reason} ->
        Logger.warning("AnalyzeCommitHotspots: failed: #{inspect(reason)}")
        reason_code = classify_error_reason(reason)

        failure =
          build_failure(reason_code, "run_analysis",
            retryable: reason_code != "diff_extract_failed",
            message: inspect(reason)
          )

        set_failure_trace_attributes(failure)
        mark_error(commit.commit_hash, inspect(reason), failure)
        :ok
    end
  end

  defp extract_diff_context(repo_path, commit_hash) do
    Tracer.with_span "spotter.commit_hotspots.diff_extract" do
      with {:ok, diff_stats} <- CommitDiffExtractor.diff_stats(repo_path, commit_hash),
           {:ok, patch_files} <- CommitPatchExtractor.patch_hunks(repo_path, commit_hash) do
        {eligible, meta} = filter_patch_files(patch_files, diff_stats.binary_files)

        Tracer.set_attribute("spotter.patch_files_total", meta.total)
        Tracer.set_attribute("spotter.patch_files_eligible", meta.eligible)
        Tracer.set_attribute("spotter.patch_files_skipped_binary", meta.skipped_binary)
        Tracer.set_attribute("spotter.patch_files_skipped_blocklist", meta.skipped_blocklist)

        {:ok, %{diff_stats: diff_stats, patch_files: eligible}}
      end
    end
  end

  @doc false
  @spec filter_patch_files([map()], [String.t()]) :: {[map()], map()}
  def filter_patch_files(patch_files, binary_files) do
    binary_set = MapSet.new(binary_files)

    {eligible, skipped_binary, skipped_blocklist} =
      Enum.reduce(patch_files, {[], 0, 0}, fn file, {acc, bin, bl} ->
        cond do
          MapSet.member?(binary_set, file.path) ->
            {acc, bin + 1, bl}

          not CommitHotspotFilters.eligible_path?(file.path) ->
            {acc, bin, bl + 1}

          true ->
            {[file | acc], bin, bl}
        end
      end)

    eligible = Enum.reverse(eligible)
    total = length(patch_files)

    meta = %{
      total: total,
      eligible: length(eligible),
      skipped_binary: skipped_binary,
      skipped_blocklist: skipped_blocklist
    }

    {eligible, meta}
  end

  defp persist_hotspots(project_id, commit, result) do
    now = DateTime.utc_now()

    Enum.each(result.hotspots, fn h ->
      Ash.create(CommitHotspot, %{
        project_id: project_id,
        commit_id: commit.id,
        relative_path: h.relative_path,
        line_start: h.line_start,
        line_end: h.line_end,
        symbol_name: h.symbol_name,
        snippet: h.snippet,
        reason: h.reason,
        overall_score: h.overall_score,
        rubric: h.rubric,
        model_used: result.metadata[:model_used] || "unknown",
        analyzed_at: now,
        metadata: result.metadata
      })
    end)

    ensure_hotspot_review_items(project_id, commit)
  end

  defp ensure_hotspot_review_items(project_id, commit) do
    hotspots =
      CommitHotspot
      |> Ash.Query.filter(commit_id == ^commit.id)
      |> Ash.read!()

    Enum.each(hotspots, fn hotspot ->
      existing =
        ReviewItem
        |> Ash.Query.filter(
          project_id == ^project_id and
            target_kind == :commit_hotspot and
            commit_hotspot_id == ^hotspot.id
        )
        |> Ash.Query.limit(1)
        |> Ash.read!()

      if existing == [] do
        Ash.create(ReviewItem, %{
          project_id: project_id,
          target_kind: :commit_hotspot,
          commit_id: commit.id,
          commit_hotspot_id: hotspot.id,
          importance: importance_from_score(hotspot.overall_score),
          interval_days: 4,
          next_due_on: Date.utc_today()
        })
      end
    end)
  end

  defp importance_from_score(score) when score >= 70, do: :high
  defp importance_from_score(score) when score >= 40, do: :medium
  defp importance_from_score(_), do: :low

  defp mark_success(commit, metadata) do
    Ash.update(commit, %{
      hotspots_status: :ok,
      hotspots_analyzed_at: DateTime.utc_now(),
      hotspots_error: nil,
      hotspots_metadata: metadata
    })

    :ok
  end

  defp mark_error(commit_hash_or_commit, error_msg, failure) do
    commit =
      case commit_hash_or_commit do
        %Commit{} = c ->
          c

        hash when is_binary(hash) ->
          case load_commit(hash) do
            {:ok, c} -> c
            _ -> nil
          end
      end

    if commit do
      metadata = if failure == %{}, do: %{}, else: %{"failure" => failure}

      Ash.update(commit, %{
        hotspots_status: :error,
        hotspots_error: String.slice(error_msg, 0, 500),
        hotspots_metadata: metadata
      })
    end
  end

  # -- Failure contract helpers --

  defp build_failure(reason_code, stage, opts) do
    %{
      "reason_code" => reason_code,
      "stage" => stage,
      "retryable" => Keyword.get(opts, :retryable, false),
      "error_class" => Keyword.get(opts, :error_class),
      "message" => opts |> Keyword.get(:message) |> truncate_message(),
      "details" => Keyword.get(opts, :details, %{})
    }
  end

  defp set_failure_trace_attributes(failure) do
    Tracer.set_attribute("spotter.failure.reason_code", failure["reason_code"])
    Tracer.set_attribute("spotter.failure.stage", failure["stage"])
    Tracer.set_attribute("spotter.failure.retryable", failure["retryable"])

    if failure["error_class"] do
      Tracer.set_attribute("spotter.failure.error_class", failure["error_class"])
    end
  end

  defp classify_error_reason(reason) do
    case reason do
      :diff_extract_failed -> "diff_extract_failed"
      {:agent_timeout, _} -> "agent_timeout"
      _ -> "agent_error"
    end
  end

  defp truncate_message(nil), do: nil
  defp truncate_message(msg) when is_binary(msg), do: String.slice(msg, 0, 500)
  defp truncate_message(msg), do: msg |> inspect() |> String.slice(0, 500)
end
