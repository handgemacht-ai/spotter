defmodule Spotter.Services.CommitHotspotAgent do
  @moduledoc """
  Orchestrates commit hotspot analysis using Claude via `claude_agent_sdk`.

  Implements a size-aware strategy:
  - Small diffs: single main run (Haiku)
  - Large diffs: explore-only run (Haiku) to select relevant regions,
    then chunked main runs (Haiku)
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Services.ClaudeCode.Client
  alias Spotter.Services.CommitHotspotChunker
  alias Spotter.Services.LlmCredentials

  # Thresholds for choosing strategy
  @default_max_files 200
  @default_max_changed_lines 2000
  @default_max_patch_bytes 500_000

  # Models
  @explore_model "claude-haiku-4-5-20251001"
  @main_model "claude-haiku-4-5-20251001"

  @explore_prompt """
  You are a code review triage analyst. Given diff statistics and hunk summaries for a commit,
  select which file regions are worth deep analysis for code quality hotspots.

  Focus on:
  - Complex logic changes (not just formatting or imports)
  - Error-prone patterns
  - Files with significant additions (not just deletions)

  Skip:
  - Binary files
  - Auto-generated files (migrations, lock files, compiled assets)
  - Test fixtures and sample data
  - Trivial changes (< 3 meaningful lines)
  """

  @explore_schema %{
    "type" => "object",
    "required" => ["selected"],
    "properties" => %{
      "selected" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "required" => ["relative_path", "ranges", "reason"],
          "properties" => %{
            "relative_path" => %{"type" => "string"},
            "ranges" => %{
              "type" => "array",
              "items" => %{
                "type" => "object",
                "required" => ["line_start", "line_end"],
                "properties" => %{
                  "line_start" => %{"type" => "integer"},
                  "line_end" => %{"type" => "integer"}
                }
              }
            },
            "reason" => %{"type" => "string"}
          }
        }
      },
      "skipped" => %{
        "type" => "array",
        "items" => %{"type" => "object"}
      }
    }
  }

  @main_prompt """
  You are a senior code reviewer analyzing a commit for quality hotspots.

  For each significant code region, identify hotspots worth reviewing. Score each on:
  - **complexity**: Logic complexity (0-100)
  - **duplication**: Copy-paste risk (0-100)
  - **error_handling**: Gaps in error handling (0-100)
  - **test_coverage**: Likelihood of being untested (0-100)
  - **change_risk**: Risk of introducing bugs (0-100)

  Provide an **overall_score** (0-100) representing review priority.

  Include:
  - The enclosing function/symbol name when identifiable
  - A short snippet (max 5 lines) showing the core of the hotspot
  - A concise reason explaining why this is a hotspot
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

  @type diff_context :: %{
          diff_stats: map(),
          patch_files: [map()],
          context_windows: %{String.t() => [map()]}
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
  Analyzes a commit's diff context and returns scored hotspots.

  Chooses strategy based on diff size thresholds.
  """
  @spec run(String.t(), String.t(), diff_context(), keyword()) ::
          {:ok, %{hotspots: [hotspot()], strategy: atom(), metadata: map()}} | {:error, term()}
  def run(commit_hash, commit_subject, diff_context, opts \\ []) do
    Tracer.with_span "spotter.commit_hotspots.agent.run" do
      Tracer.set_attribute("spotter.commit_hash", commit_hash)
      Tracer.set_attribute("spotter.model_explore", @explore_model)
      Tracer.set_attribute("spotter.model_main", @main_model)

      with {:ok, _key} <- LlmCredentials.anthropic_api_key() do
        strategy = choose_strategy(diff_context, opts)
        Tracer.set_attribute("spotter.strategy", Atom.to_string(strategy))

        case strategy do
          :single_run ->
            run_single(commit_hash, commit_subject, diff_context)

          :explore_then_chunked ->
            run_explore_then_chunked(commit_hash, commit_subject, diff_context, opts)
        end
      end
    end
  end

  @doc """
  Determines the analysis strategy based on diff size.
  """
  @spec choose_strategy(diff_context(), keyword()) :: :single_run | :explore_then_chunked
  def choose_strategy(diff_context, opts \\ []) do
    stats = diff_context.diff_stats

    max_files =
      Keyword.get(opts, :max_files, env_int("SPOTTER_COMMIT_MAX_FILES", @default_max_files))

    max_lines =
      Keyword.get(
        opts,
        :max_changed_lines,
        env_int("SPOTTER_COMMIT_MAX_CHANGED_LINES", @default_max_changed_lines)
      )

    max_bytes =
      Keyword.get(
        opts,
        :max_patch_bytes,
        env_int("SPOTTER_COMMIT_MAX_PATCH_BYTES", @default_max_patch_bytes)
      )

    total_lines = stats.insertions + stats.deletions
    total_patch_bytes = sum_context_bytes(diff_context.context_windows)

    exceeds_thresholds?(
      stats.files_changed,
      total_lines,
      total_patch_bytes,
      max_files,
      max_lines,
      max_bytes
    )
  end

  defp exceeds_thresholds?(files, lines, bytes, max_files, max_lines, max_bytes) do
    if files > max_files or lines > max_lines or bytes > max_bytes do
      :explore_then_chunked
    else
      :single_run
    end
  end

  defp sum_context_bytes(context_windows) do
    context_windows
    |> Enum.flat_map(fn {_path, windows} -> windows end)
    |> Enum.map(&byte_size(&1.content))
    |> Enum.sum()
  end

  # Single run: send all context windows to Haiku in one call
  defp run_single(commit_hash, commit_subject, diff_context) do
    Tracer.with_span "spotter.commit_hotspots.agent.main" do
      regions = build_all_regions(diff_context)
      input = format_main_input(commit_hash, commit_subject, regions)

      case Client.query_json_schema(@main_prompt, input, @main_schema,
             model: @main_model,
             timeout_ms: 120_000
           ) do
        {:ok, %{output: output, model_used: model_used}} ->
          Tracer.set_attribute("spotter.model_used_main", model_used || @main_model)

          case validate_main_output(output) do
            {:ok, hotspots} ->
              {:ok,
               %{
                 hotspots: hotspots,
                 strategy: :single_run,
                 metadata: %{
                   chunk_count: 1,
                   eligible_files: map_size(diff_context.context_windows)
                 }
               }}

            {:error, _} = err ->
              err
          end

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          {:error, reason}
      end
    end
  end

  # Explore then chunked: Haiku selects regions, Haiku analyzes in chunks
  defp run_explore_then_chunked(commit_hash, commit_subject, diff_context, opts) do
    explore_input = format_explore_input(diff_context)

    explore_result =
      Tracer.with_span "spotter.commit_hotspots.agent.explore" do
        case Client.query_json_schema(@explore_prompt, explore_input, @explore_schema,
               model: @explore_model,
               timeout_ms: 60_000
             ) do
          {:ok, %{output: output, model_used: model_used}} ->
            Tracer.set_attribute("spotter.model_used_explore", model_used || @explore_model)
            validate_explore_output(output)

          {:error, reason} ->
            Tracer.set_status(:error, inspect(reason))
            {:error, reason}
        end
      end

    with {:ok, selected, skipped_count} <- explore_result do
      run_chunked_main(commit_hash, commit_subject, selected, skipped_count, diff_context, opts)
    end
  end

  defp run_chunked_main(
         commit_hash,
         commit_subject,
         selected,
         skipped_count,
         diff_context,
         opts
       ) do
    selected_regions = build_selected_regions(selected, diff_context)
    chunks = CommitHotspotChunker.chunk_regions(selected_regions, opts)
    chunk_plan = CommitHotspotChunker.chunk_plan(chunks)

    Tracer.set_attribute("spotter.chunk_count", length(chunks))

    all_hotspots = analyze_chunks(chunks, commit_hash, commit_subject)

    {:ok,
     %{
       hotspots: dedupe_hotspots(all_hotspots),
       strategy: :explore_then_chunked,
       metadata: %{
         chunk_count: length(chunks),
         chunk_plan: chunk_plan,
         eligible_files: length(selected),
         skipped_files: skipped_count
       }
     }}
  end

  defp analyze_chunks(chunks, commit_hash, commit_subject) do
    Enum.flat_map(chunks, fn chunk_regions ->
      input = format_main_input(commit_hash, commit_subject, chunk_regions)
      analyze_single_chunk(input)
    end)
  end

  defp analyze_single_chunk(input) do
    case Client.query_json_schema(@main_prompt, input, @main_schema,
           model: @main_model,
           timeout_ms: 120_000
         ) do
      {:ok, %{output: output}} ->
        case validate_main_output(output) do
          {:ok, hotspots} -> hotspots
          {:error, _} -> []
        end

      {:error, _} ->
        []
    end
  end

  # --- Input formatting ---

  defp format_explore_input(diff_context) do
    stats = diff_context.diff_stats

    stats_section = """
    ## Diff Statistics
    Files changed: #{stats.files_changed}
    Insertions: #{stats.insertions}
    Deletions: #{stats.deletions}
    Binary files: #{Enum.join(stats.binary_files, ", ")}
    """

    hunks_section =
      diff_context.patch_files
      |> Enum.map_join("\n\n", &format_file_hunks/1)

    "#{stats_section}\n## Per-file Hunk Summaries\n#{hunks_section}"
  end

  defp format_file_hunks(file) do
    hunk_summaries =
      Enum.map_join(file.hunks, "\n", fn h ->
        excerpt = h.lines |> Enum.take(3) |> Enum.join("\n  ")

        "  Lines #{h.new_start}-#{h.new_start + h.new_len - 1} (+#{h.new_len} lines):\n  #{excerpt}"
      end)

    "### #{file.path}\n#{hunk_summaries}"
  end

  defp format_main_input(commit_hash, commit_subject, regions) do
    regions_text =
      Enum.map_join(regions, "\n\n---\n\n", fn region ->
        line_range = "#{region[:line_start] || "?"}\u2013#{region[:line_end] || "?"}"
        "### #{region.relative_path} (lines #{line_range})\n```\n#{region.content}\n```"
      end)

    "Commit: #{String.slice(commit_hash, 0, 8)} \u2014 #{commit_subject}\n\n#{regions_text}"
  end

  # --- Region building ---

  defp build_all_regions(diff_context) do
    Enum.flat_map(diff_context.context_windows, fn {path, windows} ->
      Enum.map(windows, &window_to_region(path, &1))
    end)
  end

  defp build_selected_regions(selected, diff_context) do
    Enum.flat_map(selected, fn sel ->
      path = sel["relative_path"]
      sel_ranges = sel["ranges"] || []

      case Map.get(diff_context.context_windows, path) do
        nil -> []
        windows -> filter_overlapping_windows(windows, sel_ranges, path)
      end
    end)
  end

  defp filter_overlapping_windows(windows, sel_ranges, path) do
    windows
    |> Enum.filter(&window_overlaps_any_range?(&1, sel_ranges))
    |> Enum.map(&window_to_region(path, &1))
  end

  defp window_overlaps_any_range?(window, ranges) do
    Enum.any?(ranges, fn r ->
      window.line_start <= (r["line_end"] || r["line_start"]) and
        window.line_end >= (r["line_start"] || window.line_start)
    end)
  end

  defp window_to_region(path, window) do
    %{
      relative_path: path,
      line_start: window.line_start,
      line_end: window.line_end,
      content: window.content
    }
  end

  # --- Response validation ---

  defp validate_explore_output(%{"selected" => selected} = output) when is_list(selected) do
    skipped_count =
      case output["skipped"] do
        list when is_list(list) -> length(list)
        _ -> 0
      end

    {:ok, selected, skipped_count}
  end

  defp validate_explore_output(_), do: {:error, :invalid_explore_response}

  defp validate_main_output(%{"hotspots" => hotspots}) when is_list(hotspots) do
    {:ok, Enum.map(hotspots, &normalize_hotspot/1)}
  end

  defp validate_main_output(_), do: {:error, :invalid_main_response}

  @doc false
  def parse_explore_response(raw) when is_binary(raw) do
    case parse_json(raw) do
      {:ok, map} ->
        case validate_explore_output(map) do
          {:ok, selected, _skipped} -> {:ok, selected}
          {:error, _} = err -> err
        end

      {:error, _} = err ->
        err
    end
  end

  def parse_explore_response(%{} = map) do
    case validate_explore_output(map) do
      {:ok, selected, _skipped} -> {:ok, selected}
      {:error, _} = err -> err
    end
  end

  @doc false
  def parse_main_response(raw) when is_binary(raw) do
    case parse_json(raw) do
      {:ok, map} -> validate_main_output(map)
      {:error, _} = err -> err
    end
  end

  def parse_main_response(%{} = map), do: validate_main_output(map)

  defp normalize_hotspot(h) do
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

  defp env_int(var, default) do
    case System.get_env(var) do
      nil -> default
      val -> String.to_integer(val)
    end
  end
end
