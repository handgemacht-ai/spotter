defmodule Spotter.Services.CommitHotspotAgent do
  @moduledoc """
  Runs commit hotspot analysis as a single Claude Agent SDK tool loop.

  The agent reads diff stats and patch hunks, uses the MCP
  `repo_read_file_at_commit` tool to fetch code snippets on demand,
  and returns scored hotspots in strict JSON.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Agents.HotspotTools
  alias Spotter.Agents.HotspotToolServer
  alias Spotter.Observability.AgentRunInput
  alias Spotter.Observability.AgentRunScope
  alias Spotter.Observability.ClaudeAgentFlow
  alias Spotter.Observability.ErrorReport
  alias Spotter.Observability.FlowKeys
  alias Spotter.Services.ClaudeCode.ResultExtractor
  alias Spotter.Telemetry.TraceContext

  @model "claude-sonnet-4-5-20250929"
  @max_turns 12
  @timeout_ms 300_000

  @system_prompt """
  You are a senior code reviewer analyzing a Git commit for quality hotspots.

  ## Workflow

  1. Read the diff stats and hunk ranges provided in the user prompt.
  2. Select up to 25 file regions that are worth deep analysis.
     Focus on complex logic changes, error-prone patterns, and files with
     significant additions. Skip binary files, auto-generated files
     (migrations, lock files, compiled assets), test fixtures, and trivial
     changes (< 3 meaningful lines).
  3. For each selected region, call
     `mcp__spotter-hotspots__repo_read_file_at_commit` with the commit hash,
     file path, and line range (use line_start/line_end with context).
  4. Analyze the fetched code and identify hotspots worth reviewing.

  ## Scope Rules

  **Prefer function/symbol-scoped snippets over file-level entries.**
  Each hotspot must target a specific function, macro, or code block — not
  an entire file. Keep snippets to at most 12 lines showing the core issue.

  ## Rubric

  Score each hotspot on (0-100):
  - **complexity**: Logic complexity
  - **duplication**: Copy-paste risk
  - **error_handling**: Gaps in error handling
  - **test_coverage**: Likelihood of being untested
  - **change_risk**: Risk of introducing bugs

  Deterministic pre-scores are provided in the user prompt. Use them as
  context. Return an **llm_adjustment** (-10 to 10) for each hotspot
  representing your additional insight beyond the deterministic score.
  Positive values raise priority, negative values lower it.

  Include:
  - The enclosing function/symbol name when identifiable
  - A short snippet (max 5 lines) showing the core of the hotspot
  - A concise reason explaining why this is a hotspot

  ## Output

  Return strict JSON matching the required schema. Do not wrap output in
  markdown fences. If no hotspots are found, return {"hotspots": []}.
  """

  @main_schema %{
    "type" => "object",
    "required" => ["hotspots"],
    "properties" => %{
      "hotspots" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "required" => [
            "relative_path",
            "line_start",
            "line_end",
            "snippet",
            "reason",
            "overall_score",
            "llm_adjustment",
            "rubric"
          ],
          "properties" => %{
            "relative_path" => %{"type" => "string"},
            "symbol_name" => %{"type" => ["string", "null"]},
            "line_start" => %{"type" => "integer"},
            "line_end" => %{"type" => "integer"},
            "snippet" => %{"type" => "string"},
            "reason" => %{"type" => "string"},
            "overall_score" => %{"type" => "number"},
            "llm_adjustment" => %{"type" => "number"},
            "rubric" => %{
              "type" => "object",
              "required" => [
                "complexity",
                "duplication",
                "error_handling",
                "test_coverage",
                "change_risk"
              ],
              "properties" => %{
                "complexity" => %{"type" => "number"},
                "duplication" => %{"type" => "number"},
                "error_handling" => %{"type" => "number"},
                "test_coverage" => %{"type" => "number"},
                "change_risk" => %{"type" => "number"}
              }
            }
          }
        }
      }
    }
  }

  @type hotspot :: %{
          relative_path: String.t(),
          symbol_name: String.t() | nil,
          line_start: integer(),
          line_end: integer(),
          snippet: String.t(),
          reason: String.t(),
          overall_score: float(),
          llm_adjustment: float(),
          rubric: map()
        }

  @doc """
  Runs hotspot analysis for a commit using a single agent tool loop.

  ## Input map (required keys)

  - `:project_id` — UUID string
  - `:commit_hash` — 40-hex commit hash
  - `:commit_subject` — commit subject line (optional, defaults to `""`)
  - `:diff_stats` — map from `CommitDiffExtractor.diff_stats/2`
  - `:patch_files` — list of eligible patch hunks
  - `:git_cwd` — repo path string
  """
  @spec run(map(), keyword()) ::
          {:ok, %{hotspots: [hotspot()], metadata: map()}} | {:error, term()}
  @hotspot_required_keys ~w(project_id commit_hash diff_stats patch_files git_cwd)a
  @hotspot_optional_keys [{:commit_subject, ""}, :run_id]

  def run(input, _opts \\ []) do
    case AgentRunInput.normalize(input, @hotspot_required_keys, @hotspot_optional_keys) do
      {:error, {:missing_keys, keys}} ->
        {:error, {:invalid_input, keys}}

      {:ok, normalized} ->
        do_run(normalized)
    end
  end

  defp do_run(
         %{
           project_id: project_id,
           commit_hash: commit_hash,
           diff_stats: diff_stats,
           patch_files: patch_files,
           git_cwd: git_cwd
         } = input
       ) do
    commit_subject = Map.get(input, :commit_subject, "")

    Tracer.with_span "spotter.commit_hotspots.agent.run" do
      Tracer.set_attribute("spotter.project_id", project_id)
      Tracer.set_attribute("spotter.commit_hash", commit_hash)
      Tracer.set_attribute("spotter.model_requested", @model)
      Tracer.set_attribute("spotter.max_turns", @max_turns)
      Tracer.set_attribute("spotter.timeout_ms", @timeout_ms)
      Tracer.set_attribute("spotter.patch_files_eligible", length(patch_files))

      HotspotTools.Helpers.set_git_cwd(git_cwd)
      server = HotspotToolServer.create_server()

      AgentRunScope.put(server.registry_pid, %{
        project_id: project_id,
        commit_hash: commit_hash,
        git_cwd: git_cwd,
        run_id: Map.get(input, :run_id),
        agent_kind: "hotspot"
      })

      metrics_candidates = Map.get(input, :metrics_candidates, [])

      user_prompt =
        build_user_prompt(
          commit_hash,
          commit_subject,
          diff_stats,
          patch_files,
          metrics_candidates
        )

      sdk_opts =
        %ClaudeAgentSDK.Options{
          model: @model,
          system_prompt: @system_prompt,
          max_turns: @max_turns,
          timeout_ms: @timeout_ms,
          output_format: {:json_schema, @main_schema},
          tools: [],
          allowed_tools: HotspotToolServer.allowed_tools(),
          permission_mode: :dont_ask,
          mcp_servers: %{"spotter-hotspots" => server}
        }
        |> ClaudeAgentFlow.build_opts()

      flow_keys = [FlowKeys.project(project_id), FlowKeys.commit(commit_hash)]
      run_id = Map.get(input, :run_id)
      traceparent = TraceContext.current_traceparent()

      try do
        messages =
          user_prompt
          |> ClaudeAgentSDK.query(sdk_opts)
          |> ClaudeAgentFlow.wrap_stream(
            flow_keys: flow_keys,
            run_id: run_id,
            traceparent: traceparent
          )
          |> Enum.to_list()

        build_result(messages)
      rescue
        e ->
          reason = Exception.message(e)
          Logger.warning("CommitHotspotAgent: failed: #{reason}")
          Tracer.set_attribute("spotter.error.kind", "exception")
          Tracer.set_attribute("spotter.error.reason", String.slice(reason, 0, 500))
          ErrorReport.set_trace_error("agent_error", reason, "services.commit_hotspot_agent")
          {:error, {:agent_error, reason}}
      catch
        :exit, exit_reason ->
          msg = "CommitHotspotAgent: SDK process exited: #{inspect(exit_reason)}"
          Logger.warning(msg)
          Tracer.set_attribute("spotter.error.kind", "exit")
          Tracer.set_attribute("spotter.error.reason", String.slice(msg, 0, 500))
          ErrorReport.set_trace_error("agent_exit", msg, "services.commit_hotspot_agent")
          {:error, {:agent_exit, exit_reason}}
      after
        AgentRunScope.delete(server.registry_pid)
        HotspotTools.Helpers.set_git_cwd(nil)
      end
    end
  end

  defp build_result(messages) do
    case ResultExtractor.extract_structured_output(messages) do
      {:ok, output} ->
        case validate_main_output(output) do
          {:ok, hotspots} ->
            model_used = ResultExtractor.extract_model_used(messages)
            tool_counts = extract_tool_counts(messages)

            {:ok,
             %{
               hotspots: hotspots,
               metadata: %{
                 model_used: model_used || @model,
                 tool_counts: tool_counts
               }
             }}

          {:error, _} ->
            {:error, :invalid_structured_output}
        end

      {:error, _} ->
        {:error, :no_structured_output}
    end
  rescue
    e ->
      Logger.warning("CommitHotspotAgent: build_result crashed: #{Exception.message(e)}")
      {:error, :invalid_structured_output}
  end

  # --- Prompt building ---

  defp build_user_prompt(
         commit_hash,
         commit_subject,
         diff_stats,
         patch_files,
         metrics_candidates
       ) do
    stats_json = Jason.encode!(diff_stats)
    patches_json = Jason.encode!(Enum.map(patch_files, &summarize_patch_file/1))

    metrics_section =
      if metrics_candidates != [] do
        metrics_json = Jason.encode!(Enum.map(metrics_candidates, &summarize_metrics_candidate/1))

        """

        ## Deterministic Pre-Scores
        These are computed deterministically. Use them as context for your llm_adjustment.
        #{metrics_json}
        """
      else
        ""
      end

    """
    Commit: #{String.slice(commit_hash, 0, 8)} — #{commit_subject}
    Full hash: #{commit_hash}

    ## Diff Statistics
    #{stats_json}

    ## Patch Files (eligible hunks)
    #{patches_json}
    #{metrics_section}
    """
  end

  defp summarize_metrics_candidate(candidate) do
    %{
      path: candidate.relative_path,
      line_start: candidate.line_start,
      line_end: candidate.line_end,
      symbol_name: candidate.symbol_name,
      scores: candidate.metrics
    }
  end

  defp summarize_patch_file(file) do
    %{
      path: file.path,
      hunks:
        Enum.map(file.hunks, fn h ->
          %{
            new_start: h.new_start,
            new_len: h.new_len,
            header: Map.get(h, :header, ""),
            excerpt: h.lines |> Enum.take(5) |> Enum.join("\n")
          }
        end)
    }
  end

  # --- Response validation ---

  defp validate_main_output(%{"hotspots" => hotspots}) when is_list(hotspots) do
    normalized = hotspots |> Enum.map(&normalize_hotspot/1) |> Enum.reject(&is_nil/1)
    {:ok, normalized}
  end

  defp validate_main_output(_), do: {:error, :invalid_main_response}

  @doc false
  def parse_main_response(raw) when is_binary(raw) do
    case parse_json(raw) do
      {:ok, map} -> validate_main_output(map)
      {:error, _} = err -> err
    end
  end

  def parse_main_response(%{} = map), do: validate_main_output(map)

  defp normalize_hotspot(h) when is_map(h) do
    %{
      relative_path: h["relative_path"] || "",
      symbol_name: h["symbol_name"],
      line_start: h["line_start"] || 0,
      line_end: h["line_end"] || 0,
      snippet: h["snippet"] || "",
      reason: h["reason"] || "",
      overall_score: clamp(h["overall_score"] || 0),
      llm_adjustment: clamp_adjustment(h["llm_adjustment"] || 0),
      rubric: parse_rubric(h["rubric"])
    }
  end

  defp normalize_hotspot(_), do: nil

  defp parse_rubric(nil), do: %{}

  defp parse_rubric(rubric) when is_map(rubric),
    do: Map.new(rubric, fn {k, v} -> {k, clamp(v)} end)

  defp parse_rubric(_), do: %{}

  @doc false
  def dedupe_hotspots(hotspots) do
    hotspots
    |> Enum.group_by(&{&1.relative_path, &1.line_start, &1.line_end, &1.symbol_name})
    |> Enum.map(fn {_key, group} -> Enum.max_by(group, & &1.overall_score) end)
  end

  # --- Scoring V2 integration ---

  @v2_weights %{
    complexity: 0.30,
    churn: 0.25,
    blast_radius: 0.30,
    test_exposure: 0.15
  }

  @max_snippet_span 80
  @max_snippet_lines 12
  @max_file_loc_for_whole_file 120

  @doc """
  Merges deterministic metrics into agent-produced hotspots using weighted scoring.

  For each hotspot, finds the closest matching deterministic candidate and computes:
  `overall_score = clamp(base_score + llm_adjustment, 0, 100)`

  Returns hotspots with updated `overall_score` and `metadata.scoring_version`.
  """
  @spec apply_scoring_v2([hotspot()], [map()]) :: {[hotspot()], map()}
  def apply_scoring_v2(hotspots, metrics_candidates) do
    Tracer.with_span "spotter.commit_hotspots.agent.scoring_v2" do
      Tracer.set_attribute("spotter.scoring_version", "hotspot_v2")

      metrics_index = index_metrics(metrics_candidates)

      {scored, rejected_count} =
        hotspots
        |> Enum.map(&merge_candidate_score(&1, metrics_index))
        |> enforce_snippet_constraints()

      Tracer.set_attribute("spotter.llm_adjustment_applied", length(scored))
      Tracer.set_attribute("spotter.rejected_candidates", rejected_count)

      {scored, %{scoring_version: "hotspot_v2", rejected_candidates: rejected_count}}
    end
  end

  defp index_metrics(candidates) do
    Map.new(candidates, fn c ->
      {{c.relative_path, c.line_start, c.line_end}, c.metrics}
    end)
  end

  defp merge_candidate_score(hotspot, metrics_index) do
    metrics = find_matching_metrics(hotspot, metrics_index)

    if metrics do
      base_score = compute_base_score(metrics)
      adj = hotspot.llm_adjustment
      final = clamp_score(base_score + adj)

      %{hotspot | overall_score: final}
      |> Map.put(:deterministic_metrics, metrics)
      |> Map.put(:base_score, Float.round(base_score, 2))
    else
      hotspot
    end
  end

  defp find_matching_metrics(hotspot, metrics_index) do
    # Exact match first
    exact_key = {hotspot.relative_path, hotspot.line_start, hotspot.line_end}

    case Map.get(metrics_index, exact_key) do
      nil -> find_overlapping_metrics(hotspot, metrics_index)
      metrics -> metrics
    end
  end

  defp find_overlapping_metrics(hotspot, metrics_index) do
    # Find best overlapping candidate for the same file
    metrics_index
    |> Enum.filter(fn {{path, m_start, m_end}, _} ->
      path == hotspot.relative_path and
        ranges_overlap?(hotspot.line_start, hotspot.line_end, m_start, m_end)
    end)
    |> Enum.max_by(
      fn {{_, m_start, m_end}, _} ->
        overlap_size(hotspot.line_start, hotspot.line_end, m_start, m_end)
      end,
      fn -> nil end
    )
    |> case do
      {_key, metrics} -> metrics
      nil -> nil
    end
  end

  defp ranges_overlap?(a_start, a_end, b_start, b_end),
    do: a_start <= b_end and b_start <= a_end

  defp overlap_size(a_start, a_end, b_start, b_end),
    do: max(0, min(a_end, b_end) - max(a_start, b_start) + 1)

  @doc false
  def compute_base_score(metrics) do
    w = @v2_weights

    w.complexity * Map.get(metrics, :complexity_score, 0) +
      w.churn * Map.get(metrics, :change_churn_score, 0) +
      w.blast_radius * Map.get(metrics, :blast_radius_score, 0) +
      w.test_exposure * Map.get(metrics, :test_exposure_score, 0)
  end

  @doc """
  Enforces snippet-level constraints on hotspot candidates.

  Rejects:
  - Candidates where `(line_end - line_start + 1) > 80`
  - Whole-file ranges when file has > 120 LOC (approximated by line_end)
  - Truncates snippet to 12 lines
  """
  @spec enforce_snippet_constraints([hotspot()]) :: {[hotspot()], non_neg_integer()}
  def enforce_snippet_constraints(hotspots) do
    {kept, rejected} =
      Enum.split_with(hotspots, fn h ->
        span = h.line_end - h.line_start + 1
        span <= @max_snippet_span and not whole_file_range?(h)
      end)

    trimmed = Enum.map(kept, &trim_snippet/1)
    {trimmed, length(rejected)}
  end

  defp whole_file_range?(hotspot) do
    hotspot.line_start <= 1 and hotspot.line_end > @max_file_loc_for_whole_file
  end

  defp trim_snippet(hotspot) do
    lines = String.split(hotspot.snippet, "\n")

    if length(lines) > @max_snippet_lines do
      trimmed = lines |> Enum.take(@max_snippet_lines) |> Enum.join("\n")
      %{hotspot | snippet: trimmed}
    else
      hotspot
    end
  end

  defp clamp_score(n) when is_number(n), do: n |> max(0.0) |> min(100.0) |> Float.round(1)
  defp clamp_score(_), do: 0.0

  # --- Tool counting ---

  @doc false
  def extract_tool_counts(messages) when is_list(messages) do
    allowed = MapSet.new(HotspotToolServer.allowed_tools())

    messages
    |> Enum.flat_map(&extract_tool_names/1)
    |> Enum.filter(&MapSet.member?(allowed, &1))
    |> Enum.frequencies()
  rescue
    _ -> %{}
  end

  def extract_tool_counts(_), do: %{}

  defp extract_tool_names(%{type: "assistant", message: %{content: content}})
       when is_list(content) do
    for %{"type" => "tool_use", "name" => name} <- content, do: name
  end

  defp extract_tool_names(%{type: "assistant", message: %{"content" => content}})
       when is_list(content) do
    for %{"type" => "tool_use", "name" => name} <- content, do: name
  end

  defp extract_tool_names(%ClaudeAgentSDK.Message{
         type: :assistant,
         data: %{message: %{content: content}}
       })
       when is_list(content) do
    for %{"type" => "tool_use", "name" => name} <- content, do: name
  end

  defp extract_tool_names(%ClaudeAgentSDK.Message{
         type: :assistant,
         data: %{message: %{"content" => content}}
       })
       when is_list(content) do
    for %{"type" => "tool_use", "name" => name} <- content, do: name
  end

  defp extract_tool_names(_), do: []

  # --- Helpers ---

  defp parse_json(text) do
    cleaned =
      text
      |> String.replace(~r/^```(?:json)?\s*/m, "")
      |> String.replace(~r/\s*```\s*$/m, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:json_parse_error, reason}}
    end
  end

  defp clamp(n) when is_number(n), do: n |> max(0) |> min(100) |> Kernel.*(1.0) |> Float.round(1)
  defp clamp(_), do: 0.0

  defp clamp_adjustment(n) when is_number(n),
    do: n |> max(-10) |> min(10) |> Kernel.*(1.0) |> Float.round(1)

  defp clamp_adjustment(_), do: 0.0
end
