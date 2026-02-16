defmodule Spotter.Services.CommitHotspotMetrics do
  @moduledoc """
  Deterministic hotspot metrics service that computes maintainability risk
  signals before the LLM finalization step.

  Produces per-snippet scores for complexity, change churn, test exposure,
  and blast radius using deterministic formulas. No LLM calls.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Services.GitRunner

  @git_timeout_ms 15_000
  @grep_max_bytes 500_000

  @doc """
  Builds candidate metrics for all eligible patch hunks.

  ## Input

  A map with keys:

    * `:commit_hash` — 40-hex commit hash
    * `:diff_stats` — map from `CommitDiffExtractor.diff_stats/2`
    * `:patch_files` — list from `CommitPatchExtractor.patch_hunks/2` (already filtered)
    * `:git_cwd` — repo path string

  ## Returns

    * `{:ok, [candidate_metrics]}` — list of metrics maps per snippet
    * `{:error, term}` — on failure
  """
  @spec build_candidate_metrics(map()) :: {:ok, [map()]} | {:error, term()}
  def build_candidate_metrics(%{patch_files: []}), do: {:ok, []}

  def build_candidate_metrics(%{
        commit_hash: commit_hash,
        diff_stats: diff_stats,
        patch_files: patch_files,
        git_cwd: git_cwd
      }) do
    Tracer.with_span "spotter.commit_hotspots.metrics.compute" do
      Tracer.set_attribute("spotter.commit_hash", commit_hash)
      Tracer.set_attribute("spotter.patch_files_eligible", length(patch_files))

      file_stats_index = index_file_stats(diff_stats)

      candidates =
        patch_files
        |> Enum.flat_map(fn patch_file ->
          build_file_candidates(patch_file, file_stats_index, commit_hash, git_cwd)
        end)

      Tracer.set_attribute("spotter.metrics_candidates", length(candidates))

      {:ok, candidates}
    end
  rescue
    e ->
      Logger.error("CommitHotspotMetrics failed: #{Exception.message(e)}")
      {:error, {:metrics_error, Exception.message(e)}}
  end

  def build_candidate_metrics(_invalid), do: {:ok, []}

  # -- Private --

  defp index_file_stats(%{file_stats: file_stats}) when is_list(file_stats) do
    Map.new(file_stats, fn fs -> {fs.path, fs} end)
  end

  defp index_file_stats(_), do: %{}

  defp build_file_candidates(patch_file, file_stats_index, commit_hash, git_cwd) do
    path = patch_file.path
    hunks = patch_file[:hunks] || []
    file_stat = Map.get(file_stats_index, path, %{added: 0, deleted: 0})

    hunks
    |> Enum.filter(&(&1.new_len > 0))
    |> Enum.map(fn hunk ->
      line_start = hunk.new_start
      line_end = hunk.new_start + max(hunk.new_len - 1, 0)
      lines = hunk[:lines] || []
      symbol_name = detect_symbol_name(lines, hunk[:header])

      complexity = compute_complexity(lines, hunk.new_len)
      churn = compute_change_churn(file_stat, hunk)
      test_exposure = compute_test_exposure(path)

      {blast_radius, fan_in, module_spread, br_confidence} =
        compute_blast_radius(symbol_name, path, commit_hash, git_cwd)

      %{
        relative_path: path,
        line_start: line_start,
        line_end: line_end,
        symbol_name: symbol_name,
        metrics: %{
          complexity_score: complexity,
          change_churn_score: churn,
          test_exposure_score: test_exposure,
          blast_radius_score: blast_radius,
          fan_in_estimate: fan_in,
          module_spread_estimate: module_spread,
          blast_radius_confidence: br_confidence
        }
      }
    end)
  end

  @doc false
  def detect_symbol_name(lines, header) do
    # Try header first (e.g., "@@ -10,5 +10,7 @@ def my_function(...)")
    with_header = extract_symbol_from_header(header)
    if with_header, do: with_header, else: extract_symbol_from_lines(lines)
  end

  defp extract_symbol_from_header(nil), do: nil
  defp extract_symbol_from_header(""), do: nil

  defp extract_symbol_from_header(header) when is_binary(header) do
    # Match Elixir def/defp/defmacro/defmacrop in hunk header context
    case Regex.run(~r/\b(defp?|defmacrop?)\s+([a-z_][a-z0-9_?!]*)/, header) do
      [_, _kind, name] -> name
      _ -> nil
    end
  end

  defp extract_symbol_from_lines(lines) when is_list(lines) do
    Enum.find_value(lines, fn line ->
      case Regex.run(~r/^\s*(defp?|defmacrop?)\s+([a-z_][a-z0-9_?!]*)/, line) do
        [_, _kind, name] -> name
        _ -> nil
      end
    end)
  end

  defp extract_symbol_from_lines(_), do: nil

  @doc false
  def compute_complexity(lines, loc) when is_list(lines) do
    branch_points = count_branch_points(lines)
    nesting_depth = estimate_max_nesting(lines)
    bool_ops = count_bool_ops(lines)

    score = branch_points * 12 + nesting_depth * 8 + bool_ops * 4 + max(0, loc - 15) * 1.5
    min(100.0, score / 1) |> Float.round(2)
  end

  def compute_complexity(_, _), do: 0.0

  defp count_branch_points(lines) do
    Enum.count(lines, fn line ->
      Regex.match?(~r/\b(if|unless|case|cond|with|rescue|catch|fn\s)\b/, line)
    end)
  end

  defp estimate_max_nesting(lines) do
    # Approximate nesting by tracking indent depth changes
    lines
    |> Enum.map(fn line ->
      case Regex.run(~r/^(\s*)/, line) do
        [_, spaces] -> div(String.length(spaces), 2)
        _ -> 0
      end
    end)
    |> Enum.max(fn -> 0 end)
    |> then(&max(&1 - 1, 0))
  end

  defp count_bool_ops(lines) do
    Enum.reduce(lines, 0, fn line, acc ->
      matches = Regex.scan(~r/\b(and|or|not|&&|\|\||!)\b/, line)
      acc + length(matches)
    end)
  end

  @doc false
  def compute_change_churn(file_stat, hunk) do
    file_added = Map.get(file_stat, :added, 0)
    file_deleted = Map.get(file_stat, :deleted, 0)

    # Use hunk contribution scaled by file totals
    hunk_lines = length(hunk[:lines] || [])
    total_file_changes = max(file_added + file_deleted, 1)
    hunk_weight = min(1.0, hunk_lines / total_file_changes)

    effective_added = file_added * hunk_weight
    effective_deleted = file_deleted * hunk_weight

    score = effective_added * 2 + effective_deleted * 1.5
    min(100.0, score * 1.0) |> Float.round(2)
  end

  @doc false
  def compute_test_exposure(path) when is_binary(path) do
    cond do
      String.starts_with?(path, "test/") -> 100.0
      String.ends_with?(path, "_test.exs") -> 100.0
      true -> compute_test_exposure_heuristic(path)
    end
  end

  def compute_test_exposure(_), do: 70.0

  defp compute_test_exposure_heuristic(path) do
    # Estimate: test files typically mirror source paths
    # Without running a full test coverage check, use 70 as baseline
    # (will be refined by blast radius fallback in the future)
    test_path_guess = path_to_test_path(path)

    # For now, use baseline — nearby_test_hits defaults to 0
    # Formula: max(0, 70 - nearby_test_hits * 20)
    # With 0 hits, score is 70
    _ = test_path_guess
    nearby_test_hits = 0
    max(0.0, 70.0 - nearby_test_hits * 20) |> Float.round(2)
  end

  defp path_to_test_path(path) do
    path
    |> String.replace_prefix("lib/", "test/")
    |> String.replace_suffix(".ex", "_test.exs")
  end

  @doc false
  def compute_blast_radius(symbol_name, path, commit_hash, git_cwd) do
    Tracer.with_span "spotter.commit_hotspots.metrics.blast_radius" do
      {fan_in, module_spread, fallback?} =
        if symbol_name do
          scan_symbol_references(symbol_name, path, commit_hash, git_cwd)
        else
          scan_path_references(path, commit_hash, git_cwd)
        end

      Tracer.set_attribute("spotter.blast_radius.fallback_count", if(fallback?, do: 1, else: 0))

      score = min(100.0, (fan_in * 10 + module_spread * 8) * 1.0) |> Float.round(2)
      confidence = classify_blast_confidence(symbol_name, fan_in, fallback?)

      {score, fan_in, module_spread, confidence}
    end
  end

  defp classify_blast_confidence(_symbol_name, _fan_in, true = _fallback?), do: "low"
  defp classify_blast_confidence(_symbol_name, 0, _fallback?), do: "low"
  defp classify_blast_confidence(name, fan_in, _) when name != nil and fan_in >= 3, do: "high"

  defp classify_blast_confidence(name, fan_in, _) when name != nil and fan_in in 1..2,
    do: "medium"

  defp classify_blast_confidence(_, _, _), do: "low"

  defp scan_symbol_references(symbol_name, source_path, commit_hash, git_cwd) do
    # Search for symbol usage across the repo at the given commit
    pattern = "\\b#{Regex.escape(symbol_name)}\\b"

    case git_grep(pattern, commit_hash, git_cwd) do
      {:ok, output} ->
        {fan_in, module_spread} = parse_grep_results(output, source_path)
        {fan_in, module_spread, false}

      {:error, _} ->
        {0, 0, true}
    end
  end

  defp scan_path_references(path, commit_hash, git_cwd) do
    # Fallback: search for module name derived from path
    module_name = path_to_module_fragment(path)

    if module_name do
      case git_grep(module_name, commit_hash, git_cwd) do
        {:ok, output} ->
          {fan_in, module_spread} = parse_grep_results(output, path)
          {fan_in, module_spread, true}

        {:error, _} ->
          {0, 0, true}
      end
    else
      {0, 0, true}
    end
  end

  defp git_grep(pattern, commit_hash, git_cwd) do
    args = ["grep", "-c", "-E", pattern, commit_hash, "--", "*.ex", "*.exs"]

    GitRunner.run(args, cd: git_cwd, timeout_ms: @git_timeout_ms, max_bytes: @grep_max_bytes)
  end

  @doc false
  def parse_grep_results(output, source_path) when is_binary(output) do
    lines =
      output
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn line ->
        # Format: "commit_hash:path:count"
        case String.split(line, ":", parts: 3) do
          [_hash, file_path, count_str] ->
            count = String.to_integer(String.trim(count_str))
            [{file_path, count}]

          _ ->
            []
        end
      end)
      |> Enum.reject(fn {file_path, _} -> file_path == source_path end)

    fan_in = length(lines)

    module_spread =
      lines
      |> Enum.map(fn {file_path, _} -> extract_module_dir(file_path) end)
      |> Enum.uniq()
      |> length()

    {fan_in, module_spread}
  end

  def parse_grep_results(_, _), do: {0, 0}

  defp extract_module_dir(path) do
    path
    |> Path.dirname()
    |> String.split("/")
    |> Enum.take(3)
    |> Enum.join("/")
  end

  defp path_to_module_fragment(path) do
    # Convert "lib/spotter/services/foo.ex" -> "Spotter.Services.Foo"
    path
    |> String.replace_prefix("lib/", "")
    |> String.replace_suffix(".ex", "")
    |> String.replace_suffix(".exs", "")
    |> String.split("/")
    |> Enum.map_join(".", &Macro.camelize/1)
    |> then(fn
      "" -> nil
      name -> name
    end)
  end
end
