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
  alias Spotter.Observability.AgentRunScope
  alias Spotter.Observability.ClaudeAgentFlow
  alias Spotter.Observability.ErrorReport
  alias Spotter.Observability.FlowKeys
  alias Spotter.Services.ClaudeCode.ResultExtractor

  @model "claude-opus-4-6-20250918"
  @max_turns 12
  @timeout_ms 180_000

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

  ## Rubric

  Score each hotspot on (0-100):
  - **complexity**: Logic complexity
  - **duplication**: Copy-paste risk
  - **error_handling**: Gaps in error handling
  - **test_coverage**: Likelihood of being untested
  - **change_risk**: Risk of introducing bugs

  Provide an **overall_score** (0-100) representing review priority.

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
          rubric: map()
        }

  @doc """
  Runs hotspot analysis for a commit using a single agent tool loop.

  ## Input map (required keys)

  - `:project_id` — UUID string
  - `:commit_hash` — 40-hex commit hash
  - `:commit_subject` — commit subject line (may be empty)
  - `:diff_stats` — map from `CommitDiffExtractor.diff_stats/2`
  - `:patch_files` — list of eligible patch hunks
  - `:git_cwd` — repo path string
  """
  @spec run(map(), keyword()) ::
          {:ok, %{hotspots: [hotspot()], metadata: map()}} | {:error, term()}
  def run(input, _opts \\ []) do
    %{
      project_id: project_id,
      commit_hash: commit_hash,
      commit_subject: commit_subject,
      diff_stats: diff_stats,
      patch_files: patch_files,
      git_cwd: git_cwd
    } = input

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

      user_prompt = build_user_prompt(commit_hash, commit_subject, diff_stats, patch_files)

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

      try do
        messages =
          user_prompt
          |> ClaudeAgentSDK.query(sdk_opts)
          |> ClaudeAgentFlow.wrap_stream(flow_keys: flow_keys)
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

  defp build_user_prompt(commit_hash, commit_subject, diff_stats, patch_files) do
    stats_json = Jason.encode!(diff_stats)
    patches_json = Jason.encode!(Enum.map(patch_files, &summarize_patch_file/1))

    """
    Commit: #{String.slice(commit_hash, 0, 8)} — #{commit_subject}
    Full hash: #{commit_hash}

    ## Diff Statistics
    #{stats_json}

    ## Patch Files (eligible hunks)
    #{patches_json}
    """
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
end
