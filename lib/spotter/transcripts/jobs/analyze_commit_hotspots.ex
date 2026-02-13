defmodule Spotter.Transcripts.Jobs.AnalyzeCommitHotspots do
  @moduledoc "Oban worker that analyzes a commit's diff and persists hotspots + review items."

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id, :commit_hash], period: 3600]

  require Ash.Query
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Services.{
    CommitContextBuilder,
    CommitDiffExtractor,
    CommitHotspotAgent,
    CommitHotspotFilters,
    CommitPatchExtractor
  }

  alias Spotter.Transcripts.{Commit, CommitHotspot, ReviewItem, Session}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "commit_hash" => commit_hash}}) do
    Tracer.with_span "spotter.commit_hotspots.analyze.perform" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.commit_hash", commit_hash)

      case {load_commit(commit_hash), resolve_repo_path(project_id)} do
        {{:ok, commit}, {:ok, repo_path}} ->
          run_analysis(project_id, commit, repo_path)

        {{:error, reason}, _} ->
          Logger.warning("AnalyzeCommitHotspots: commit not found: #{inspect(reason)}")
          :ok

        {_, :no_cwd} ->
          mark_error(commit_hash, "no accessible repo path")
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

  defp run_analysis(project_id, commit, repo_path) do
    with {:ok, diff_context} <- extract_diff_context(repo_path, commit.commit_hash),
         {:ok, result} <-
           CommitHotspotAgent.run(commit.commit_hash, commit.subject || "", diff_context) do
      persist_hotspots(project_id, commit, result)
      mark_success(commit, result.metadata)
    else
      {:error, :missing_api_key} ->
        Logger.warning("AnalyzeCommitHotspots: missing API key, skipping")
        mark_error(commit.commit_hash, "missing_api_key")
        :ok

      {:error, reason} ->
        Logger.warning("AnalyzeCommitHotspots: failed: #{inspect(reason)}")
        mark_error(commit.commit_hash, inspect(reason))
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

        context_windows = build_context_windows(repo_path, eligible)

        Tracer.set_attribute("spotter.eligible_files", map_size(context_windows))

        {:ok,
         %{
           diff_stats: diff_stats,
           patch_files: eligible,
           context_windows: context_windows
         }}
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

  defp build_context_windows(repo_path, patch_files) do
    Map.new(patch_files, fn file ->
      ranges =
        Enum.map(file.hunks, fn h ->
          {h.new_start, h.new_start + max(h.new_len - 1, 0)}
        end)

      content = read_file_content(repo_path, file.path)
      windows = CommitContextBuilder.build_windows(content, ranges)

      {file.path, windows}
    end)
  end

  defp read_file_content(repo_path, relative_path) do
    full_path = Path.join(repo_path, relative_path)

    case File.read(full_path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
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
        model_used: model_for_strategy(result.strategy),
        analyzed_at: now,
        metadata: %{strategy: Atom.to_string(result.strategy)}
      })
    end)

    ensure_hotspot_review_items(project_id, commit)
  end

  defp model_for_strategy(:single_run), do: "claude-opus-4-6"
  defp model_for_strategy(:explore_then_chunked), do: "claude-opus-4-6+haiku"
  defp model_for_strategy(_), do: "unknown"

  defp ensure_hotspot_review_items(project_id, commit) do
    hotspots =
      CommitHotspot
      |> Ash.Query.filter(commit_id == ^commit.id)
      |> Ash.read!()

    Enum.each(hotspots, fn hotspot ->
      Ash.create(ReviewItem, %{
        project_id: project_id,
        target_kind: :commit_hotspot,
        commit_id: commit.id,
        commit_hotspot_id: hotspot.id,
        importance: importance_from_score(hotspot.overall_score),
        interval_days: 4,
        next_due_on: Date.add(Date.utc_today(), 4)
      })
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

  defp mark_error(commit_hash_or_commit, error_msg) do
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
      Ash.update(commit, %{
        hotspots_status: :error,
        hotspots_error: String.slice(error_msg, 0, 500)
      })
    end
  end
end
