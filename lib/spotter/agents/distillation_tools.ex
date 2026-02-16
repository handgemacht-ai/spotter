defmodule Spotter.Agents.DistillationTools do
  @moduledoc """
  In-process MCP tools for session and project rollup distillation.

  Provides validation and normalization for structured distillation payloads.
  Tools return sanitized payloads as JSON text results for downstream persistence.
  """

  use ClaudeAgentSDK.Tool

  alias Spotter.Observability.AgentRunScope

  # ── Limits ──

  @max_what_changed 12
  @max_commands_run 20
  @max_open_threads 10
  @max_risks 10
  @max_key_files 20
  @max_important_snippets 12
  @max_notable_commits 20
  @max_themes 12
  @max_source_sections 20
  @max_notes 10

  @max_summary_len 1200
  @max_path_len 400
  @max_reason_len 320
  @max_symbol_name_len 200
  @max_snippet_len 1200

  # ── Session Tool ──

  deftool :record_session_distillation,
          "Record a validated session distillation payload with summary, snippets, and metadata",
          %{
            type: "object",
            properties: %{
              session_summary: %{type: "string", description: "Concise summary of the session"},
              what_changed: %{
                type: "array",
                items: %{type: "string"},
                description: "List of changes made"
              },
              commands_run: %{
                type: "array",
                items: %{type: "string"},
                description: "Commands executed during the session"
              },
              open_threads: %{
                type: "array",
                items: %{type: "string"},
                description: "Unfinished threads of work"
              },
              risks: %{
                type: "array",
                items: %{type: "string"},
                description: "Identified risks"
              },
              key_files: %{
                type: "array",
                items: %{
                  type: "object",
                  required: ["path"],
                  properties: %{
                    path: %{type: "string", description: "Repo-relative file path"},
                    reason: %{type: "string", description: "Why this file is key"}
                  }
                },
                description: "Important files touched or referenced"
              },
              important_snippets: %{
                type: "array",
                items: %{
                  type: "object",
                  required: [
                    "relative_path",
                    "line_start",
                    "line_end",
                    "snippet",
                    "why_important"
                  ],
                  properties: %{
                    relative_path: %{type: "string", description: "Repo-relative file path"},
                    line_start: %{type: "integer", description: "Start line (1-based)"},
                    line_end: %{type: "integer", description: "End line (1-based)"},
                    snippet: %{type: "string", description: "Code snippet text"},
                    why_important: %{type: "string", description: "Why this snippet matters"},
                    symbol_name: %{type: "string", description: "Symbol name (optional)"}
                  }
                },
                description: "Important code snippets"
              },
              distillation_metadata: %{
                type: "object",
                required: ["confidence", "source_sections"],
                properties: %{
                  confidence: %{
                    type: "number",
                    description: "Confidence score 0.0-1.0"
                  },
                  source_sections: %{
                    type: "array",
                    items: %{type: "string"},
                    description: "Sections of input that informed the distillation"
                  },
                  notes: %{
                    type: "array",
                    items: %{type: "string"},
                    description: "Optional notes"
                  }
                },
                description: "Metadata about the distillation process"
              }
            },
            required: [
              "session_summary",
              "what_changed",
              "commands_run",
              "open_threads",
              "risks",
              "key_files",
              "important_snippets",
              "distillation_metadata"
            ]
          } do
    require OpenTelemetry.Tracer, as: Tracer
    alias Spotter.Agents.DistillationTools, as: DT

    def execute(input) do
      Tracer.with_span "spotter.distillation.tool.record_session" do
        case DT.validate_session(input) do
          {:ok, payload} ->
            Tracer.set_attribute(
              "spotter.snippet_count",
              length(payload.important_snippets)
            )

            Tracer.set_attribute("spotter.key_file_count", length(payload.key_files))
            DT.store_result({:ok, :session, payload})
            DT.text_result(%{ok: true, kind: "session", payload: payload})

          {:error, details} ->
            DT.store_result({:error, details})
            DT.text_result(%{ok: false, error: "validation_error", details: details})
        end
      end
    end
  end

  # ── Project Rollup Tool ──

  deftool :record_project_rollup_distillation,
          "Record a validated project rollup distillation payload with period summary, themes, and metadata",
          %{
            type: "object",
            properties: %{
              period_summary: %{
                type: "string",
                description: "Summary of the project activity period"
              },
              themes: %{
                type: "array",
                items: %{type: "string"},
                description: "Recurring themes"
              },
              notable_commits: %{
                type: "array",
                items: %{
                  type: "object",
                  required: ["hash", "why_it_matters"],
                  properties: %{
                    hash: %{type: "string", description: "Commit hash"},
                    why_it_matters: %{
                      type: "string",
                      description: "Why this commit is notable"
                    }
                  }
                },
                description: "Notable commits in the period"
              },
              open_threads: %{
                type: "array",
                items: %{type: "string"},
                description: "Unfinished threads"
              },
              risks: %{
                type: "array",
                items: %{type: "string"},
                description: "Identified risks"
              },
              important_snippets: %{
                type: "array",
                items: %{
                  type: "object",
                  required: [
                    "relative_path",
                    "line_start",
                    "line_end",
                    "snippet",
                    "why_important"
                  ],
                  properties: %{
                    relative_path: %{type: "string", description: "Repo-relative file path"},
                    line_start: %{type: "integer", description: "Start line (1-based)"},
                    line_end: %{type: "integer", description: "End line (1-based)"},
                    snippet: %{type: "string", description: "Code snippet text"},
                    why_important: %{type: "string", description: "Why this snippet matters"},
                    symbol_name: %{type: "string", description: "Symbol name (optional)"}
                  }
                },
                description: "Important code snippets (may be empty)"
              },
              distillation_metadata: %{
                type: "object",
                required: ["confidence", "source_sections"],
                properties: %{
                  confidence: %{
                    type: "number",
                    description: "Confidence score 0.0-1.0"
                  },
                  source_sections: %{
                    type: "array",
                    items: %{type: "string"},
                    description: "Sections of input that informed the distillation"
                  },
                  notes: %{
                    type: "array",
                    items: %{type: "string"},
                    description: "Optional notes"
                  }
                },
                description: "Metadata about the distillation process"
              }
            },
            required: [
              "period_summary",
              "themes",
              "notable_commits",
              "open_threads",
              "risks",
              "important_snippets",
              "distillation_metadata"
            ]
          } do
    require OpenTelemetry.Tracer, as: Tracer
    alias Spotter.Agents.DistillationTools, as: DT

    def execute(input) do
      Tracer.with_span "spotter.distillation.tool.record_project_rollup" do
        case DT.validate_project_rollup(input) do
          {:ok, payload} ->
            Tracer.set_attribute(
              "spotter.snippet_count",
              length(payload.important_snippets)
            )

            Tracer.set_attribute(
              "spotter.notable_commit_count",
              length(payload.notable_commits)
            )

            DT.store_result({:ok, :project_rollup, payload})
            DT.text_result(%{ok: true, kind: "project_rollup", payload: payload})

          {:error, details} ->
            DT.store_result({:error, details})
            DT.text_result(%{ok: false, error: "validation_error", details: details})
        end
      end
    end
  end

  # ── Public API ──

  @doc "Returns all tool modules for MCP server registration."
  def all_tool_modules do
    __MODULE__
    |> ClaudeAgentSDK.Tool.list_tools()
    |> Enum.map(& &1.module)
  end

  @doc false
  def text_result(data) do
    {:ok, %{"content" => [%{"type" => "text", "text" => Jason.encode!(data)}]}}
  end

  @distillation_result_table Spotter.Observability.AgentRunScope

  @doc """
  Stores a distillation result in the shared ETS table, keyed by the
  current process's agent scope registry pid. Called from tool handlers
  which run in spawned processes.
  """
  def store_result(result) do
    AgentRunScope.ensure_table_exists()

    case resolve_registry_pid() do
      pid when is_pid(pid) ->
        :ets.insert(@distillation_result_table, {{:distillation_result, pid}, result})

      nil ->
        :ok
    end
  end

  defp resolve_registry_pid do
    case Process.get(:claude_agent_sdk_tool_registry_pid) do
      pid when is_pid(pid) ->
        pid

      _ ->
        (Process.get(:"$ancestors", []) ++ Process.get(:"$callers", []))
        |> Enum.find(fn pid -> is_pid(pid) and AgentRunScope.get(pid) != :error end)
    end
  end

  @doc """
  Fetches and deletes the distillation result stored by a tool handler.
  Called from the agent runner after the SDK query completes.
  """
  def fetch_result(registry_pid) do
    AgentRunScope.ensure_table_exists()
    key = {:distillation_result, registry_pid}

    case :ets.lookup(@distillation_result_table, key) do
      [{^key, result}] ->
        :ets.delete(@distillation_result_table, key)
        result

      _ ->
        nil
    end
  rescue
    ArgumentError -> nil
  end

  # ── Session Validation ──

  @session_list_fields ~w(what_changed commands_run open_threads risks key_files important_snippets)

  @doc false
  def validate_session(input) do
    input = input |> normalize_nil_lists(@session_list_fields) |> normalize_metadata_notes()

    with {:ok, summary} <-
           validate_string(input["session_summary"], "session_summary", @max_summary_len),
         {:ok, what_changed} <-
           validate_string_list(
             input["what_changed"],
             "what_changed",
             @max_what_changed,
             @max_reason_len
           ),
         {:ok, commands_run} <-
           validate_string_list(
             input["commands_run"],
             "commands_run",
             @max_commands_run,
             @max_reason_len
           ),
         {:ok, open_threads} <-
           validate_string_list(
             input["open_threads"],
             "open_threads",
             @max_open_threads,
             @max_reason_len
           ),
         {:ok, risks} <-
           validate_string_list(input["risks"], "risks", @max_risks, @max_reason_len),
         {:ok, key_files} <- validate_key_files(input["key_files"]),
         {:ok, snippets} <- validate_snippets(input["important_snippets"]),
         {:ok, metadata} <- validate_metadata(input["distillation_metadata"]) do
      {:ok,
       %{
         session_summary: summary,
         what_changed: what_changed,
         commands_run: commands_run,
         open_threads: open_threads,
         risks: risks,
         key_files: key_files,
         important_snippets: snippets,
         distillation_metadata: metadata
       }}
    end
  end

  # ── Project Rollup Validation ──

  @rollup_list_fields ~w(themes notable_commits open_threads risks important_snippets)

  @doc false
  def validate_project_rollup(input) do
    input = input |> normalize_nil_lists(@rollup_list_fields) |> normalize_metadata_notes()

    with {:ok, summary} <-
           validate_string(input["period_summary"], "period_summary", @max_summary_len),
         {:ok, themes} <-
           validate_string_list(input["themes"], "themes", @max_themes, @max_reason_len),
         {:ok, commits} <- validate_notable_commits(input["notable_commits"]),
         {:ok, open_threads} <-
           validate_string_list(
             input["open_threads"],
             "open_threads",
             @max_open_threads,
             @max_reason_len
           ),
         {:ok, risks} <-
           validate_string_list(input["risks"], "risks", @max_risks, @max_reason_len),
         {:ok, snippets} <- validate_snippets(input["important_snippets"]),
         {:ok, metadata} <- validate_metadata(input["distillation_metadata"]) do
      {:ok,
       %{
         period_summary: summary,
         themes: themes,
         notable_commits: commits,
         open_threads: open_threads,
         risks: risks,
         important_snippets: snippets,
         distillation_metadata: metadata
       }}
    end
  end

  # ── Normalization ──

  defp normalize_nil_lists(input, fields) do
    Enum.reduce(fields, input, fn field, acc ->
      case Map.get(acc, field) do
        nil -> Map.put(acc, field, [])
        _ -> acc
      end
    end)
  end

  defp normalize_metadata_notes(%{"distillation_metadata" => %{"notes" => nil} = meta} = input) do
    Map.put(input, "distillation_metadata", Map.put(meta, "notes", []))
  end

  defp normalize_metadata_notes(input), do: input

  # ── Validators ──

  defp validate_each(items, validator) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, idx}, {:ok, acc} ->
      case validator.(item, idx) do
        {:ok, val} -> {:cont, {:ok, acc ++ [val]}}
        {:error, errs} -> {:halt, {:error, errs}}
      end
    end)
  end

  defp validate_string(nil, field, _max), do: {:error, ["#{field} is required"]}

  defp validate_string(val, field, max) when is_binary(val) do
    trimmed = String.trim(val)

    cond do
      trimmed == "" -> {:error, ["#{field} must not be empty"]}
      String.length(trimmed) > max -> {:error, ["#{field} exceeds max length #{max}"]}
      true -> {:ok, trimmed}
    end
  end

  defp validate_string(_, field, _max), do: {:error, ["#{field} must be a string"]}

  defp validate_string_list(nil, field, _max_count, _max_len),
    do: {:error, ["#{field} is required"]}

  defp validate_string_list(items, field, max_count, max_len) when is_list(items) do
    if length(items) > max_count do
      {:error, ["#{field} exceeds max count #{max_count}"]}
    else
      validate_each(items, fn item, idx ->
        validate_string(item, "#{field}[#{idx}]", max_len)
      end)
    end
  end

  defp validate_string_list(_, field, _max_count, _max_len),
    do: {:error, ["#{field} must be an array"]}

  defp validate_key_files(nil), do: {:error, ["key_files is required"]}

  defp validate_key_files(items) when is_list(items) do
    if length(items) > @max_key_files do
      {:error, ["key_files exceeds max count #{@max_key_files}"]}
    else
      validate_each(items, &validate_key_file/2)
    end
  end

  defp validate_key_files(_), do: {:error, ["key_files must be an array"]}

  defp validate_key_file(item, idx) when is_map(item) do
    with {:ok, path} <- validate_path(item["path"], "key_files[#{idx}].path"),
         {:ok, reason} <-
           validate_optional_string(item["reason"], "key_files[#{idx}].reason", @max_reason_len) do
      file = %{path: path}
      file = if reason, do: Map.put(file, :reason, reason), else: file
      {:ok, file}
    end
  end

  defp validate_key_file(_, idx), do: {:error, ["key_files[#{idx}] must be an object"]}

  defp validate_snippets(nil), do: {:error, ["important_snippets is required"]}

  defp validate_snippets(items) when is_list(items) do
    if length(items) > @max_important_snippets do
      {:error, ["important_snippets exceeds max count #{@max_important_snippets}"]}
    else
      validate_each(items, &validate_snippet/2)
    end
  end

  defp validate_snippets(_), do: {:error, ["important_snippets must be an array"]}

  defp validate_snippet(item, idx) when is_map(item) do
    prefix = "important_snippets[#{idx}]"

    with {:ok, path} <- validate_path(item["relative_path"], "#{prefix}.relative_path"),
         {:ok, line_start} <- validate_line(item["line_start"], "#{prefix}.line_start"),
         {:ok, line_end} <- validate_line_end(item["line_end"], line_start, "#{prefix}.line_end"),
         {:ok, snippet} <- validate_string(item["snippet"], "#{prefix}.snippet", @max_snippet_len),
         {:ok, why} <-
           validate_string(item["why_important"], "#{prefix}.why_important", @max_reason_len),
         {:ok, symbol} <-
           validate_optional_string(
             item["symbol_name"],
             "#{prefix}.symbol_name",
             @max_symbol_name_len
           ) do
      result = %{
        relative_path: path,
        line_start: line_start,
        line_end: line_end,
        snippet: snippet,
        why_important: why
      }

      result = if symbol, do: Map.put(result, :symbol_name, symbol), else: result
      {:ok, result}
    end
  end

  defp validate_snippet(_, idx),
    do: {:error, ["important_snippets[#{idx}] must be an object"]}

  defp validate_notable_commits(nil), do: {:error, ["notable_commits is required"]}

  defp validate_notable_commits(items) when is_list(items) do
    if length(items) > @max_notable_commits do
      {:error, ["notable_commits exceeds max count #{@max_notable_commits}"]}
    else
      validate_each(items, &validate_notable_commit/2)
    end
  end

  defp validate_notable_commits(_), do: {:error, ["notable_commits must be an array"]}

  defp validate_notable_commit(item, idx) when is_map(item) do
    prefix = "notable_commits[#{idx}]"

    with {:ok, hash} <- validate_string(item["hash"], "#{prefix}.hash", @max_path_len),
         {:ok, why} <-
           validate_string(item["why_it_matters"], "#{prefix}.why_it_matters", @max_reason_len) do
      {:ok, %{hash: hash, why_it_matters: why}}
    end
  end

  defp validate_notable_commit(_, idx),
    do: {:error, ["notable_commits[#{idx}] must be an object"]}

  defp validate_metadata(nil), do: {:error, ["distillation_metadata is required"]}

  defp validate_metadata(meta) when is_map(meta) do
    with {:ok, confidence} <- validate_confidence(meta["confidence"]),
         {:ok, sections} <-
           validate_string_list(
             meta["source_sections"],
             "distillation_metadata.source_sections",
             @max_source_sections,
             @max_reason_len
           ),
         {:ok, notes} <-
           validate_optional_string_list(
             meta["notes"],
             "distillation_metadata.notes",
             @max_notes,
             @max_reason_len
           ) do
      result = %{confidence: confidence, source_sections: sections}
      result = if notes, do: Map.put(result, :notes, notes), else: result
      {:ok, result}
    end
  end

  defp validate_metadata(_), do: {:error, ["distillation_metadata must be an object"]}

  defp validate_confidence(nil), do: {:error, ["distillation_metadata.confidence is required"]}

  defp validate_confidence(val) when is_number(val) do
    if val >= 0 and val <= 1 do
      {:ok, val}
    else
      {:error, ["distillation_metadata.confidence must be between 0 and 1"]}
    end
  end

  defp validate_confidence(_),
    do: {:error, ["distillation_metadata.confidence must be a number"]}

  defp validate_path(nil, field), do: {:error, ["#{field} is required"]}

  defp validate_path(val, field) when is_binary(val) do
    trimmed = String.trim(val)

    cond do
      trimmed == "" ->
        {:error, ["#{field} must not be empty"]}

      String.length(trimmed) > @max_path_len ->
        {:error, ["#{field} exceeds max length #{@max_path_len}"]}

      String.starts_with?(trimmed, "/") ->
        {:error, ["#{field} must not be an absolute path"]}

      String.contains?(trimmed, "..") ->
        {:error, ["#{field} must not contain path traversal (..)"]}

      String.contains?(trimmed, "\\") ->
        {:error, ["#{field} must not contain backslashes"]}

      true ->
        {:ok, trimmed}
    end
  end

  defp validate_path(_, field), do: {:error, ["#{field} must be a string"]}

  defp validate_line(nil, field), do: {:error, ["#{field} is required"]}

  defp validate_line(val, field) when is_integer(val) do
    if val >= 1 do
      {:ok, val}
    else
      {:error, ["#{field} must be >= 1"]}
    end
  end

  defp validate_line(_, field), do: {:error, ["#{field} must be an integer"]}

  defp validate_line_end(nil, _start, field), do: {:error, ["#{field} is required"]}

  defp validate_line_end(val, start, field) when is_integer(val) do
    cond do
      val < 1 -> {:error, ["#{field} must be >= 1"]}
      val < start -> {:error, ["#{field} must be >= line_start"]}
      true -> {:ok, val}
    end
  end

  defp validate_line_end(_, _start, field), do: {:error, ["#{field} must be an integer"]}

  defp validate_optional_string(nil, _field, _max), do: {:ok, nil}
  defp validate_optional_string(val, field, max), do: validate_string(val, field, max)

  defp validate_optional_string_list(nil, _field, _max_count, _max_len), do: {:ok, nil}

  defp validate_optional_string_list(items, field, max_count, max_len),
    do: validate_string_list(items, field, max_count, max_len)
end
