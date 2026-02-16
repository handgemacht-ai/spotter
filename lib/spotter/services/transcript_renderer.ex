defmodule Spotter.Services.TranscriptRenderer do
  @moduledoc """
  Pseudo-renders Claude Code transcript messages into displayable text lines.

  Converts parsed JSONL messages into a flat list of line maps that approximate
  what Claude Code renders in the terminal.
  """

  @default_visible_lines 10
  @subagent_pattern ~r/agent-[a-zA-Z0-9]+/
  @noisy_success_pattern ~r/^The file .* has been updated successfully\.$/

  @extension_to_language %{
    ".ex" => "elixir",
    ".exs" => "elixir",
    ".eex" => "elixir",
    ".heex" => "elixir",
    ".leex" => "elixir",
    ".sh" => "bash",
    ".bash" => "bash",
    ".zsh" => "bash",
    ".json" => "json",
    ".jsonl" => "json",
    ".js" => "javascript",
    ".jsx" => "javascript",
    ".ts" => "typescript",
    ".tsx" => "typescript",
    ".py" => "python",
    ".rb" => "ruby",
    ".rs" => "rust",
    ".go" => "go",
    ".yml" => "yaml",
    ".yaml" => "yaml",
    ".toml" => "toml",
    ".md" => "markdown",
    ".html" => "html",
    ".css" => "css",
    ".sql" => "sql",
    ".diff" => "diff"
  }

  @doc """
  Renders a list of parsed messages into enriched line maps.

  Each line map contains `:line`, `:message_id`, `:type`, `:line_number`,
  `:kind`, `:tool_use_id`, `:thread_key`, `:subagent_ref`, `:code_language`,
  `:render_mode`, `:source_line_number`, `:token_count_total`, `:debug_payload`,
  and tool-result group metadata.

  ## Options

    * `:session_cwd` - Session working directory for relativizing file paths.

  """
  @spec render([map()], keyword()) :: [map()]
  def render(messages, opts \\ []) do
    session_cwd = opts[:session_cwd]
    tool_use_index = build_tool_use_index(messages)
    tool_outcome_index = build_tool_outcome_index(messages)
    tool_result_timestamp_index = build_tool_result_timestamp_index(messages)

    messages
    |> Enum.flat_map(fn msg ->
      usage = extract_usage(msg)
      timestamp = extract_timestamp(msg)

      msg
      |> render_message_enriched(session_cwd, tool_use_index, tool_outcome_index)
      |> Enum.with_index()
      |> Enum.map(fn {line_meta, line_idx} ->
        line_meta
        |> Map.put(:message_id, msg[:id] || msg[:uuid])
        |> Map.put(:type, msg[:type])
        |> put_subagent_ref(msg)
        |> put_token_usage(usage, line_idx)
        |> put_timestamp(timestamp, line_idx)
        |> put_tool_duration(timestamp, tool_result_timestamp_index)
        |> put_debug_payload(msg)
      end)
    end)
    |> annotate_tool_result_groups()
    |> collapse_hook_progress_groups()
    |> annotate_token_deltas()
    |> annotate_timestamp_deltas()
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, idx} -> Map.put(entry, :line_number, idx) end)
  end

  @doc """
  Renders a single message into a list of line strings.

  Returns `[]` for non-renderable message types (progress, system, thinking, file_history_snapshot).
  """
  @spec render_message(map()) :: [String.t()]
  def render_message(%{type: type})
      when type in [:progress, :system, :thinking, :file_history_snapshot] do
    []
  end

  def render_message(%{content: nil}), do: []

  def render_message(%{type: :assistant, content: content}) do
    render_assistant_content(content)
  end

  def render_message(%{type: :user, content: content}) do
    render_user_content(content)
  end

  def render_message(_), do: []

  @doc """
  Strips ANSI escape codes from text.
  """
  @spec strip_ansi(String.t()) :: String.t()
  def strip_ansi(text) do
    Regex.replace(~r/\e\[[0-9;]*[a-zA-Z]/, text, "")
  end

  @doc """
  Extracts plain text from message content map.
  """
  @spec extract_text(map() | nil) :: String.t()
  def extract_text(nil), do: ""
  def extract_text(%{"text" => text}), do: text

  def extract_text(%{"blocks" => blocks}) when is_list(blocks) do
    blocks
    |> Enum.map(&extract_block_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("")
  end

  def extract_text(_), do: ""

  @doc """
  Converts an absolute file path to a path relative to `session_cwd`.

  Returns the original path when `session_cwd` is nil, the path is not absolute,
  or does not share the session_cwd prefix.
  """
  @spec to_relative_path(String.t(), String.t() | nil) :: String.t()
  def to_relative_path(path, nil), do: path

  def to_relative_path(path, session_cwd) do
    if String.starts_with?(path, "/") do
      relative = Path.relative_to(path, session_cwd)

      if relative == path do
        path
      else
        relative
      end
    else
      path
    end
  end

  # ── Tool use index for language inference ─────────────────────────

  defp build_tool_use_index(messages) do
    messages
    |> Enum.flat_map(&extract_tool_uses/1)
    |> Map.new()
  end

  defp extract_tool_uses(%{type: :assistant, content: %{"blocks" => blocks}})
       when is_list(blocks) do
    blocks
    |> Enum.filter(&(&1["type"] == "tool_use" && &1["id"]))
    |> Enum.map(fn block ->
      {block["id"], %{name: block["name"], input: block["input"]}}
    end)
  end

  defp extract_tool_uses(_msg), do: []

  # ── Tool outcome index (success/error from tool_result blocks) ───

  defp build_tool_outcome_index(messages) do
    messages
    |> Enum.flat_map(&extract_tool_outcomes/1)
    |> Map.new()
  end

  defp extract_tool_outcomes(%{type: :user, content: %{"blocks" => blocks}})
       when is_list(blocks) do
    blocks
    |> Enum.filter(&(&1["type"] == "tool_result" && &1["tool_use_id"]))
    |> Enum.map(fn block ->
      status = if block["is_error"] == true, do: :error, else: :success
      {block["tool_use_id"], status}
    end)
  end

  defp extract_tool_outcomes(_msg), do: []

  # ── Tool result group annotation ──────────────────────────────────

  defp annotate_tool_result_groups(lines) do
    # Count total lines per tool_result_group
    group_counts =
      lines
      |> Enum.filter(&(&1.kind == :tool_result))
      |> Enum.group_by(& &1.tool_result_group)
      |> Map.new(fn {group, group_lines} -> {group, length(group_lines)} end)

    # Track per-group line index
    {annotated, _counters} =
      Enum.map_reduce(lines, %{}, fn line, counters ->
        if line.kind == :tool_result do
          group = line.tool_result_group
          idx = Map.get(counters, group, 0) + 1
          total = Map.get(group_counts, group, 0)

          updated =
            line
            |> Map.put(:result_line_index, idx)
            |> Map.put(:result_total_lines, total)
            |> Map.put(:hidden_by_default, idx > @default_visible_lines)

          {updated, Map.put(counters, group, idx)}
        else
          line =
            line
            |> Map.put(:tool_result_group, nil)
            |> Map.put(:result_line_index, nil)
            |> Map.put(:result_total_lines, nil)
            |> Map.put(:hidden_by_default, false)

          {line, counters}
        end
      end)

    annotated
  end

  # ── Hook progress group collapsing ─────────────────────────────────

  defp collapse_hook_progress_groups(lines) do
    lines
    |> chunk_hook_groups()
    |> Enum.flat_map(fn
      {:hook_group, group_lines} ->
        emit_hook_group(group_lines)

      {:other, other_lines} ->
        other_lines
    end)
  end

  # Chunks lines into tagged groups: {:hook_group, lines} or {:other, lines}
  defp chunk_hook_groups(lines) do
    Enum.chunk_while(lines, nil, &chunk_hook_step/2, &chunk_hook_flush/1)
  end

  defp chunk_hook_step(line, nil) do
    {:cont, {hook_group_key(line), [line]}}
  end

  defp chunk_hook_step(line, {current_key, current_lines}) do
    line_key = hook_group_key(line)

    if current_key != nil and line_key == current_key do
      {:cont, {current_key, current_lines ++ [line]}}
    else
      tag = if current_key, do: :hook_group, else: :other
      {:cont, {tag, current_lines}, {line_key, [line]}}
    end
  end

  defp chunk_hook_flush(nil), do: {:cont, []}

  defp chunk_hook_flush({key, lines_acc}) do
    tag = if key, do: :hook_group, else: :other
    {:cont, {tag, lines_acc}, nil}
  end

  defp hook_group_key(%{kind: kind} = line) when kind in [:hook_progress, :hook_output] do
    {line.tool_use_id, line[:hook_event], line[:hook_name]}
  end

  defp hook_group_key(_line), do: nil

  defp emit_hook_group(group_lines) do
    first = hd(group_lines)
    count = Enum.count(group_lines, &(&1.kind == :hook_progress))

    first_uuid =
      case first[:debug_payload] do
        %{uuid: uuid} when is_binary(uuid) -> uuid
        _ -> "unknown"
      end

    tool_use_part = first.tool_use_id || "unthreaded"
    hook_event = first[:hook_event] || "unknown"
    hook_name = first[:hook_name] || "unknown"

    group_key =
      "hookgroup:#{tool_use_part}:#{hook_event}:#{hook_name}:#{first_uuid}"

    summary = %{
      line: "hooks #{hook_event} #{hook_name} (#{count})",
      kind: :hook_group,
      tool_use_id: first.tool_use_id,
      thread_key: first.thread_key,
      hook_group: group_key,
      hook_detail?: false,
      message_id: nil,
      timestamp: first[:timestamp],
      type: :progress,
      code_language: nil,
      render_mode: :plain,
      source_line_number: nil,
      tool_result_group: nil,
      result_line_index: nil,
      result_total_lines: nil,
      hidden_by_default: false,
      token_count_total: nil,
      token_count_delta: nil,
      subagent_ref: first[:subagent_ref],
      debug_payload: nil,
      timestamp_delta_seconds: nil,
      timestamp_delta_slow?: nil,
      tool_duration_seconds: nil,
      tool_duration_slow?: nil
    }

    details =
      Enum.map(group_lines, fn line ->
        line
        |> Map.put(:hook_group, group_key)
        |> Map.put(:hidden_by_default, true)
      end)

    [summary | details]
  end

  # ── Debug payload ─────────────────────────────────────────────────

  defp put_debug_payload(line_meta, msg) do
    payload = %{
      id: msg[:id],
      uuid: msg[:uuid],
      type: msg[:type],
      role: msg[:role],
      tool_use_id: line_meta[:tool_use_id],
      thread_key: line_meta[:thread_key],
      kind: line_meta[:kind],
      rendered_line: line_meta[:line],
      source_line_number: line_meta[:source_line_number],
      token_count_total: line_meta[:token_count_total]
    }

    Map.put(line_meta, :debug_payload, payload)
  end

  defp extract_usage(%{raw_payload: %{"message" => %{"usage" => %{} = usage}}}), do: usage
  defp extract_usage(_), do: nil

  # ── Timestamp metadata ──────────────────────────────────────────

  defp extract_timestamp(%{timestamp: %DateTime{} = ts}), do: ts
  defp extract_timestamp(_), do: nil

  defp put_timestamp(line_meta, nil, _line_idx) do
    line_meta
    |> Map.put(:timestamp, nil)
    |> Map.put(:timestamp_delta_seconds, nil)
    |> Map.put(:timestamp_delta_slow?, nil)
  end

  defp put_timestamp(line_meta, timestamp, 0) do
    line_meta
    |> Map.put(:timestamp, timestamp)
    |> Map.put(:timestamp_delta_seconds, nil)
    |> Map.put(:timestamp_delta_slow?, nil)
  end

  defp put_timestamp(line_meta, _timestamp, _line_idx) do
    line_meta
    |> Map.put(:timestamp, nil)
    |> Map.put(:timestamp_delta_seconds, nil)
    |> Map.put(:timestamp_delta_slow?, nil)
  end

  defp annotate_timestamp_deltas(lines) do
    {annotated, _prev} =
      Enum.map_reduce(lines, nil, fn
        %{timestamp: nil} = line, prev_ts ->
          {line, prev_ts}

        %{timestamp: current_ts} = line, nil ->
          {line, current_ts}

        %{timestamp: current_ts} = line, prev_ts ->
          delta = DateTime.diff(current_ts, prev_ts, :second)

          line =
            line
            |> Map.put(:timestamp_delta_seconds, delta)
            |> Map.put(:timestamp_delta_slow?, delta > 60)

          {line, current_ts}
      end)

    annotated
  end

  # ── Tool duration metadata ──────────────────────────────────────

  defp build_tool_result_timestamp_index(messages) do
    messages
    |> Enum.flat_map(fn
      %{type: :user, timestamp: %DateTime{} = ts, content: %{"blocks" => blocks}}
      when is_list(blocks) ->
        blocks
        |> Enum.filter(&(&1["type"] == "tool_result" && &1["tool_use_id"]))
        |> Enum.map(fn block -> {block["tool_use_id"], ts} end)

      _ ->
        []
    end)
    |> Map.new()
  end

  defp put_tool_duration(line_meta, tool_use_ts, tool_result_ts_index) do
    if line_meta[:kind] == :tool_use && line_meta[:tool_use_id] do
      case {tool_use_ts, Map.get(tool_result_ts_index, line_meta.tool_use_id)} do
        {%DateTime{} = use_ts, %DateTime{} = result_ts} ->
          duration = DateTime.diff(result_ts, use_ts, :second)

          line_meta
          |> Map.put(:tool_duration_seconds, duration)
          |> Map.put(:tool_duration_slow?, duration > 60)

        _ ->
          line_meta
          |> Map.put(:tool_duration_seconds, nil)
          |> Map.put(:tool_duration_slow?, nil)
      end
    else
      line_meta
      |> Map.put(:tool_duration_seconds, nil)
      |> Map.put(:tool_duration_slow?, nil)
    end
  end

  defp put_token_usage(line_meta, nil, _line_idx) do
    line_meta
    |> Map.put(:token_count_total, nil)
    |> Map.put(:token_count_delta, nil)
  end

  defp put_token_usage(line_meta, usage, line_idx) do
    token_count_total =
      [
        usage["input_tokens"],
        usage["output_tokens"],
        usage["cache_creation_input_tokens"],
        usage["cache_read_input_tokens"]
      ]
      |> Enum.map(fn v -> if is_integer(v), do: v, else: 0 end)
      |> Enum.sum()

    if line_idx == 0 and token_count_total > 0 do
      line_meta
      |> Map.put(:token_count_total, token_count_total)
      |> Map.put(:token_count_delta, nil)
    else
      line_meta
      |> Map.put(:token_count_total, nil)
      |> Map.put(:token_count_delta, nil)
    end
  end

  defp annotate_token_deltas(lines) do
    {annotated, _prev} =
      Enum.map_reduce(lines, nil, &compute_token_delta/2)

    annotated
  end

  defp compute_token_delta(%{token_count_total: nil} = line, prev_total) do
    {line, prev_total}
  end

  defp compute_token_delta(%{token_count_total: current_total} = line, nil) do
    {line, current_total}
  end

  defp compute_token_delta(%{token_count_total: current_total} = line, prev_total) do
    {Map.put(line, :token_count_delta, current_total - prev_total), current_total}
  end

  # ── Enriched rendering (used by render/2) ──────────────────────────

  defp render_message_enriched(%{type: :progress} = msg, _session_cwd, _tui, _toi) do
    render_hook_progress(msg)
  end

  defp render_message_enriched(%{type: type}, _session_cwd, _tool_use_index, _tool_outcome_index)
       when type in [:system, :file_history_snapshot] do
    []
  end

  defp render_message_enriched(
         %{content: nil},
         _session_cwd,
         _tool_use_index,
         _tool_outcome_index
       ),
       do: []

  defp render_message_enriched(
         %{type: :thinking, content: content},
         _session_cwd,
         _tool_use_index,
         _tool_outcome_index
       ) do
    content
    |> extract_thinking_text()
    |> String.split("\n")
    |> Enum.map(&plain_line(&1, :thinking))
  end

  defp render_message_enriched(
         %{type: :assistant, content: content},
         session_cwd,
         _tool_use_index,
         tool_outcome_index
       ) do
    render_assistant_content_enriched(content, session_cwd, tool_outcome_index)
  end

  defp render_message_enriched(
         %{type: :user} = msg,
         session_cwd,
         tool_use_index,
         _tool_outcome_index
       ) do
    render_user_content_enriched(msg, session_cwd, tool_use_index)
  end

  defp render_message_enriched(_msg, _session_cwd, _tool_use_index, _tool_outcome_index), do: []

  # ── Enriched assistant rendering ───────────────────────────────────

  defp render_assistant_content_enriched(%{"blocks" => blocks}, session_cwd, tool_outcome_index)
       when is_list(blocks) do
    Enum.flat_map(blocks, &render_assistant_block_enriched(&1, session_cwd, tool_outcome_index))
  end

  defp render_assistant_content_enriched(%{"text" => text}, _session_cwd, _tool_outcome_index) do
    classify_text_lines(String.split(text, "\n"), :text)
  end

  defp render_assistant_content_enriched(_content, _session_cwd, _tool_outcome_index), do: []

  defp render_assistant_block_enriched(
         %{"type" => "text", "text" => text},
         _session_cwd,
         _tool_outcome_index
       ) do
    classify_text_lines(String.split(text, "\n"), :text)
  end

  defp render_assistant_block_enriched(
         %{"type" => "thinking", "thinking" => text},
         _session_cwd,
         _tool_outcome_index
       ) do
    text
    |> String.split("\n")
    |> Enum.map(&plain_line(&1, :thinking))
  end

  defp render_assistant_block_enriched(
         %{"type" => "tool_use", "name" => "AskUserQuestion"} = block,
         _session_cwd,
         _tool_outcome_index
       ) do
    tool_id = block["id"]
    thread_key = tool_id || "tool-use-AskUserQuestion"
    questions = get_in(block, ["input", "questions"]) || []

    base_line = %{
      line: "● AskUserQuestion()",
      kind: :tool_use,
      tool_use_id: tool_id,
      thread_key: thread_key,
      tool_name: "AskUserQuestion",
      code_language: nil,
      render_mode: :plain,
      source_line_number: nil
    }

    question_lines =
      Enum.map(questions, fn q ->
        header = q["header"]
        question = q["question"] || ""

        line_text =
          if header && header != "" do
            "? #{header} - #{question}"
          else
            "? #{question}"
          end

        %{
          line: line_text,
          kind: :ask_user_question,
          tool_use_id: tool_id,
          thread_key: thread_key,
          code_language: nil,
          render_mode: :plain,
          source_line_number: nil
        }
      end)

    [base_line | question_lines]
  end

  defp render_assistant_block_enriched(
         %{"type" => "tool_use", "name" => "ExitPlanMode"} = block,
         _session_cwd,
         _tool_outcome_index
       ) do
    tool_id = block["id"]
    thread_key = tool_id || "tool-use-ExitPlanMode"

    [
      %{
        line: "● ExitPlanMode()",
        kind: :tool_use,
        tool_use_id: tool_id,
        thread_key: thread_key,
        tool_name: "ExitPlanMode",
        code_language: nil,
        render_mode: :plain,
        source_line_number: nil
      }
    ]
  end

  defp render_assistant_block_enriched(
         %{"type" => "tool_use", "name" => name} = block,
         session_cwd,
         tool_outcome_index
       ) do
    preview = tool_use_preview_enriched(block, session_cwd)
    tool_id = block["id"]
    thread_key = tool_id || "tool-use-#{name}"

    command_status =
      if name == "Bash" do
        case Map.get(tool_outcome_index, tool_id) do
          :error -> :error
          :success -> :success
          nil -> :pending
        end
      else
        nil
      end

    line_meta = %{
      line: "● #{name}(#{preview})",
      kind: :tool_use,
      tool_use_id: tool_id,
      thread_key: thread_key,
      tool_name: name,
      code_language: nil,
      render_mode: :plain,
      source_line_number: nil
    }

    if command_status do
      [Map.put(line_meta, :command_status, command_status)]
    else
      [line_meta]
    end
  end

  defp render_assistant_block_enriched(_block, _session_cwd, _tool_outcome_index), do: []

  # ── Enriched user rendering ────────────────────────────────────────

  defp render_user_content_enriched(
         %{content: %{"blocks" => blocks}} = msg,
         session_cwd,
         tool_use_index
       )
       when is_list(blocks) do
    Enum.flat_map(blocks, &render_user_block_enriched(&1, msg, session_cwd, tool_use_index))
  end

  defp render_user_content_enriched(
         %{content: %{"text" => text}},
         _session_cwd,
         _tool_use_index
       ) do
    classify_text_lines(String.split(text, "\n"), :text)
  end

  defp render_user_content_enriched(_msg, _session_cwd, _tool_use_index), do: []

  defp render_user_block_enriched(
         %{"type" => "tool_result"} = block,
         msg,
         session_cwd,
         tool_use_index
       ) do
    tool_use_id = block["tool_use_id"]
    tool_name = tool_name_for_result(tool_use_id, tool_use_index)
    resolved_content = resolve_tool_result_content(tool_name, block["content"], msg)
    block = Map.put(block, "content", resolved_content)

    case tool_name do
      "AskUserQuestion" ->
        render_ask_user_answer(block, msg)

      "ExitPlanMode" ->
        render_plan_decision(block, printable_line_content(resolved_content))

      "Write" ->
        if plan_write?(tool_use_id, tool_use_index) do
          render_plan_content(block, msg, tool_use_index)
        else
          render_with_diff_or_generic(block, msg, session_cwd, tool_use_index)
        end

      "Edit" ->
        render_with_diff_or_generic(block, msg, session_cwd, tool_use_index)

      _ when is_binary(resolved_content) or is_list(resolved_content) ->
        render_generic_tool_result(block, msg, session_cwd, tool_use_index)

      _ ->
        thread_key = tool_use_id || "unmatched-result"
        group_key = tool_use_id || "group-empty"

        [
          %{
            line: "(empty)",
            kind: :tool_result,
            tool_use_id: tool_use_id,
            thread_key: thread_key,
            tool_result_group: group_key,
            code_language: nil,
            render_mode: :plain,
            source_line_number: nil
          }
        ]
    end
  end

  defp render_user_block_enriched(
         %{"type" => "text", "text" => text},
         _msg,
         _session_cwd,
         _tool_use_index
       ) do
    classify_text_lines(String.split(text, "\n"), :text)
  end

  defp render_user_block_enriched(_block, _msg, _session_cwd, _tool_use_index), do: []

  # ── Tool name lookup for user result dispatch ────────────────────────

  defp tool_name_for_result(nil, _tool_use_index), do: nil

  defp tool_name_for_result(tool_use_id, tool_use_index) do
    case Map.get(tool_use_index, tool_use_id) do
      %{name: name} -> name
      _ -> nil
    end
  end

  # ── Hook progress rendering ────────────────────────────────────────

  @hook_command_max_length 120

  @hook_output_max_lines 20

  defp render_hook_progress(
         %{raw_payload: %{"data" => %{"type" => "hook_progress"} = data}} = msg
       ) do
    parent_tool_use_id =
      non_empty_string(msg.raw_payload["parentToolUseID"]) ||
        non_empty_string(msg.raw_payload["toolUseID"])

    thread_key = parent_tool_use_id || "hook-unthreaded"

    hook_event = data["hookEvent"] || "unknown"
    hook_name = data["hookName"] || "unknown"
    command = data["command"] || ""
    truncated_command = truncate_preview(command, @hook_command_max_length)

    exit_code = data["exitCode"] || data["exit_code"]
    stdout = data["stdout"]
    stderr = data["stderr"]
    duration_ms = data["durationMs"] || data["duration_ms"]

    base = %{
      tool_use_id: parent_tool_use_id,
      thread_key: thread_key,
      hook_event: hook_event,
      hook_name: hook_name,
      hook_group: nil,
      hook_detail?: true
    }

    command_row = %{
      line: "hook #{hook_event} #{hook_name}: #{truncated_command}",
      kind: :hook_progress,
      hook_command: command,
      hook_exit_code: exit_code,
      hook_stdout: stdout,
      hook_stderr: stderr,
      hook_duration_ms: duration_ms,
      code_language: nil,
      render_mode: :plain,
      source_line_number: nil
    }

    output_rows =
      hook_output_rows(exit_code, duration_ms, stdout, stderr)

    [Map.merge(base, command_row) | Enum.map(output_rows, &Map.merge(base, &1))]
  end

  defp render_hook_progress(_msg), do: []

  defp hook_output_rows(exit_code, duration_ms, stdout, stderr) do
    exit_row =
      if exit_code != nil,
        do: [hook_output_line("↳ exit_code: #{exit_code}")],
        else: []

    duration_row =
      if duration_ms != nil,
        do: [hook_output_line("↳ duration_ms: #{duration_ms}")],
        else: []

    stdout_rows = hook_stream_rows("stdout", stdout)
    stderr_rows = hook_stream_rows("stderr", stderr)

    exit_row ++ duration_row ++ stdout_rows ++ stderr_rows
  end

  defp hook_stream_rows(_label, nil), do: []
  defp hook_stream_rows(_label, ""), do: []

  defp hook_stream_rows(label, text) do
    lines = String.split(text, "\n")
    truncated? = length(lines) > @hook_output_max_lines
    visible = Enum.take(lines, @hook_output_max_lines)

    header = [hook_output_line("↳ #{label}:")]

    content =
      Enum.map(visible, fn line ->
        %{
          line: line,
          kind: :hook_output,
          code_language: "plaintext",
          render_mode: :code,
          source_line_number: nil
        }
      end)

    truncation =
      if truncated?,
        do: [hook_output_line("↳ #{label}: (truncated)")],
        else: []

    header ++ content ++ truncation
  end

  defp hook_output_line(text) do
    %{
      line: text,
      kind: :hook_output,
      code_language: nil,
      render_mode: :plain,
      source_line_number: nil
    }
  end

  defp non_empty_string(value) when is_binary(value) and value != "", do: value
  defp non_empty_string(_), do: nil

  defp safe_tool_use_result(msg, key) do
    case get_in(msg, [:raw_payload, "toolUseResult"]) do
      %{} = result -> Map.get(result, key)
      _ -> nil
    end
  end

  defp plan_write?(tool_use_id, tool_use_index) do
    case Map.get(tool_use_index, tool_use_id) do
      %{name: "Write", input: %{"file_path" => path}} when is_binary(path) ->
        Path.basename(path) == "plan.md"

      _ ->
        false
    end
  end

  # ── Special tool result renderers ────────────────────────────────────

  defp render_ask_user_answer(block, msg) do
    tool_use_id = block["tool_use_id"]
    thread_key = tool_use_id || "unmatched-result"
    answers = safe_tool_use_result(msg, "answers") || %{}

    if map_size(answers) == 0 do
      []
    else
      Enum.map(answers, fn {question, answer} ->
        %{
          line: "↳ #{question} = #{answer}",
          kind: :ask_user_answer,
          tool_use_id: tool_use_id,
          thread_key: thread_key,
          code_language: nil,
          render_mode: :plain,
          source_line_number: nil
        }
      end)
    end
  end

  defp render_plan_decision(block, content) do
    tool_use_id = block["tool_use_id"]
    thread_key = tool_use_id || "unmatched-result"

    decision =
      cond do
        content =~ "approved exiting plan mode" -> "accepted"
        content =~ "rejected exiting plan mode" or content =~ "did not approve" -> "rejected"
        true -> "unknown"
      end

    [
      %{
        line: "Plan decision: #{decision}",
        kind: :plan_decision,
        tool_use_id: tool_use_id,
        thread_key: thread_key,
        code_language: nil,
        render_mode: :plain,
        source_line_number: nil
      }
    ]
  end

  defp render_plan_content(block, msg, tool_use_index) do
    tool_use_id = block["tool_use_id"]
    plan_content = safe_tool_use_result(msg, "content") || ""

    if plan_content == "" do
      render_generic_tool_result(block, msg, nil, tool_use_index)
    else
      thread_key = tool_use_id || "unmatched-result"

      plan_content
      |> String.split("\n")
      |> Enum.map(fn line ->
        %{
          line: line,
          kind: :plan_content,
          tool_use_id: tool_use_id,
          thread_key: thread_key,
          code_language: nil,
          render_mode: :plain,
          source_line_number: nil
        }
      end)
    end
  end

  defp render_with_diff_or_generic(block, msg, session_cwd, tool_use_index) do
    is_error = block["is_error"] == true
    patches = safe_tool_use_result(msg, "structuredPatch") || []

    if not is_error and is_list(patches) and patches != [] do
      tool_use_id = block["tool_use_id"]
      file_path = resolve_diff_file_path(tool_use_id, tool_use_index, session_cwd)
      render_diff_rows(patches, tool_use_id, file_path)
    else
      block
      |> render_generic_tool_result(msg, session_cwd, tool_use_index)
      |> filter_noisy_success_lines()
    end
  end

  defp filter_noisy_success_lines(lines) do
    filtered = Enum.reject(lines, &Regex.match?(@noisy_success_pattern, &1.line))

    if filtered == [], do: [], else: filtered
  end

  defp resolve_diff_file_path(nil, _tool_use_index, _session_cwd), do: nil

  defp resolve_diff_file_path(tool_use_id, tool_use_index, session_cwd) do
    case Map.get(tool_use_index, tool_use_id) do
      %{input: %{"file_path" => path}} when is_binary(path) ->
        to_relative_path(path, session_cwd)

      _ ->
        nil
    end
  end

  defp render_diff_rows(patches, tool_use_id, file_path) do
    thread_key = tool_use_id || "unmatched-result"
    group_key = tool_use_id || "group-diff"

    file_headers =
      if file_path do
        [
          diff_line("--- a/#{file_path}", tool_use_id, thread_key, group_key),
          diff_line("+++ b/#{file_path}", tool_use_id, thread_key, group_key)
        ]
      else
        []
      end

    hunk_lines =
      Enum.flat_map(patches, fn patch ->
        old_start = patch["oldStart"] || 0
        old_lines = patch["oldLines"] || 0
        new_start = patch["newStart"] || 0
        new_lines = patch["newLines"] || 0
        header = "@@ -#{old_start},#{old_lines} +#{new_start},#{new_lines} @@"

        content_lines =
          (patch["lines"] || [])
          |> Enum.map(&diff_line(&1, tool_use_id, thread_key, group_key))

        [diff_line(header, tool_use_id, thread_key, group_key) | content_lines]
      end)

    file_headers ++ hunk_lines
  end

  defp diff_line(text, tool_use_id, thread_key, group_key) do
    %{
      line: text,
      kind: :tool_result,
      tool_use_id: tool_use_id,
      thread_key: thread_key,
      tool_result_group: group_key,
      code_language: "diff",
      render_mode: :code,
      source_line_number: nil
    }
  end

  defp render_generic_tool_result(
         %{"content" => content} = block,
         msg,
         session_cwd,
         tool_use_index
       )
       when is_binary(content) do
    tool_use_id = block["tool_use_id"]
    thread_key = tool_use_id || "unmatched-result"
    group_key = tool_use_id || "group-#{:erlang.phash2(content)}"
    tool_name = tool_name_for_result(tool_use_id, tool_use_index)
    inferred_lang = infer_result_language(tool_use_id, tool_use_index)
    start_line = extract_tool_result_start_line(msg, tool_use_id)
    force_code_mode = tool_name == "Write"

    content
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.map(fn {line, idx} ->
      relativized = relativize_in_text(line, session_cwd)

      {line_without_number, source_line_number} =
        strip_number_prefix(relativized, start_line, idx)

      {render_mode, code_language} =
        classify_result_line(relativized, inferred_lang, force_code_mode)

      %{
        line: line_without_number,
        kind: :tool_result,
        tool_use_id: tool_use_id,
        thread_key: thread_key,
        tool_result_group: group_key,
        code_language: code_language,
        render_mode: render_mode,
        source_line_number: source_line_number
      }
    end)
  end

  defp render_generic_tool_result(
         %{"content" => content} = block,
         msg,
         session_cwd,
         tool_use_index
       )
       when is_list(content) do
    tool_use_id = block["tool_use_id"]
    thread_key = tool_use_id || "unmatched-result"
    group_key = tool_use_id || "group-#{:erlang.phash2(content)}"
    tool_name = tool_name_for_result(tool_use_id, tool_use_index)
    inferred_lang = infer_result_language(tool_use_id, tool_use_index)
    start_line = extract_tool_result_start_line(msg, tool_use_id)
    force_code_mode = tool_name == "Write"

    content
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => text} -> String.split(text, "\n")
      _ -> []
    end)
    |> Enum.with_index()
    |> Enum.map(fn {line, idx} ->
      relativized = relativize_in_text(line, session_cwd)

      {line_without_number, source_line_number} =
        strip_number_prefix(relativized, start_line, idx)

      {render_mode, code_language} =
        classify_result_line(relativized, inferred_lang, force_code_mode)

      %{
        line: line_without_number,
        kind: :tool_result,
        tool_use_id: tool_use_id,
        thread_key: thread_key,
        tool_result_group: group_key,
        code_language: code_language,
        render_mode: render_mode,
        source_line_number: source_line_number
      }
    end)
  end

  defp render_generic_tool_result(block, _msg, _session_cwd, _tool_use_index) do
    tool_use_id = block["tool_use_id"]
    thread_key = tool_use_id || "unmatched-result"
    group_key = tool_use_id || "group-empty"

    [
      %{
        line: "(empty)",
        kind: :tool_result,
        tool_use_id: tool_use_id,
        thread_key: thread_key,
        tool_result_group: group_key,
        code_language: nil,
        render_mode: :plain,
        source_line_number: nil
      }
    ]
  end

  # ── Result line classification ──────────────────────────────────────

  # Numbered read output (e.g., "  1→code here") → code with inferred language
  @numbered_line_pattern ~r/^\s*\d+→/
  @numbered_line_capture ~r/^\s*(\d+)→\s?(.*)$/u

  defp classify_result_line(line, inferred_lang) do
    classify_result_line(line, inferred_lang, false)
  end

  defp classify_result_line(_line, inferred_lang, true) do
    {:code, inferred_lang || "plaintext"}
  end

  defp classify_result_line(line, inferred_lang, false) do
    if Regex.match?(@numbered_line_pattern, line) do
      {:code, inferred_lang || "plaintext"}
    else
      {:plain, nil}
    end
  end

  defp strip_number_prefix(line, start_line, idx) when is_binary(line) do
    fallback_source_line =
      if is_integer(start_line) do
        start_line + idx
      else
        nil
      end

    case Regex.run(@numbered_line_capture, line) do
      [_, parsed_line, text] ->
        source_line_number =
          if is_integer(start_line), do: start_line + idx, else: String.to_integer(parsed_line)

        {text, source_line_number}

      _ ->
        {line, fallback_source_line}
    end
  end

  defp extract_tool_result_start_line(
         %{raw_payload: %{"toolUseResult" => %{"file" => %{"startLine" => start_line}}}},
         _tool_use_id
       ) do
    parse_positive_integer(start_line)
  end

  defp extract_tool_result_start_line(%{raw_payload: %{} = payload}, tool_use_id) do
    payload
    |> get_in(["message", "content"])
    |> extract_start_line_from_blocks(tool_use_id)
  end

  defp extract_tool_result_start_line(_msg, _tool_use_id), do: nil

  defp extract_start_line_from_blocks(blocks, tool_use_id) when is_list(blocks) do
    blocks
    |> Enum.find_value(fn block ->
      if block["type"] == "tool_result" and block["tool_use_id"] == tool_use_id do
        block
        |> get_in(["toolUseResult", "file", "startLine"])
        |> parse_positive_integer()
      end
    end)
  end

  defp extract_start_line_from_blocks(_blocks, _tool_use_id), do: nil

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp parse_positive_integer(_), do: nil

  defp infer_result_language(nil, _index), do: nil

  defp infer_result_language(tool_use_id, index) do
    case Map.get(index, tool_use_id) do
      %{name: "Read", input: %{"file_path" => path}} when is_binary(path) ->
        language_from_extension(path)
      %{name: "Write", input: %{"file_path" => path}} when is_binary(path) ->
        language_from_extension(path)
      %{name: "Edit", input: %{"file_path" => path}} when is_binary(path) ->
        language_from_extension(path)

      _ ->
        nil
    end
  end

  defp resolve_tool_result_content(
         "Write",
         content,
         msg
       ) do
    case safe_tool_use_result(msg, "content") do
      content_from_result when is_binary(content_from_result) and content_from_result != "" ->
        content_from_result

      content_from_result when is_list(content_from_result) and content_from_result != [] ->
        content_from_result

      _ ->
        content
    end
  end

  defp resolve_tool_result_content(_tool_name, content, _msg), do: content

  defp printable_line_content(content) when is_binary(content), do: content

  defp printable_line_content(content), do: inspect(content)

  defp language_from_extension(path) do
    ext = Path.extname(path)
    Map.get(@extension_to_language, ext)
  end

  # ── Code detection ─────────────────────────────────────────────────

  defp classify_text_lines(lines, base_kind) do
    {result, _state} =
      Enum.reduce(lines, {[], :normal}, fn line, {acc, state} ->
        case state do
          :normal -> classify_normal_line(line, acc, base_kind)
          {:in_code, lang} -> classify_code_line(line, acc, lang, base_kind)
        end
      end)

    Enum.reverse(result)
  end

  defp classify_normal_line(line, acc, base_kind) do
    case detect_fence_open(line) do
      {lang, true} ->
        {[code_line(line, base_kind, lang) | acc], {:in_code, lang}}

      nil ->
        if Regex.match?(~r/^\s*\d+→/, line) do
          {[code_line(line, base_kind, "plaintext") | acc], :normal}
        else
          {[plain_line(line, base_kind) | acc], :normal}
        end
    end
  end

  defp classify_code_line(line, acc, lang, base_kind) do
    entry = code_line(line, base_kind, lang)

    if Regex.match?(~r/^```\s*$/, line) do
      {[entry | acc], :normal}
    else
      {[entry | acc], {:in_code, lang}}
    end
  end

  defp detect_fence_open(line) do
    case Regex.run(~r/^```(\w+)/, line) do
      [_, lang] ->
        {lang, true}

      nil ->
        if Regex.match?(~r/^```\s*$/, line) do
          {"plaintext", true}
        else
          nil
        end
    end
  end

  # ── Path relativization ────────────────────────────────────────────

  defp relativize_in_text(text, nil), do: text

  defp relativize_in_text(text, session_cwd) do
    prefix = String.trim_trailing(session_cwd, "/") <> "/"
    String.replace(text, prefix, "")
  end

  defp tool_use_preview_enriched(%{"input" => input}, session_cwd) when is_map(input) do
    input
    |> pick_tool_use_preview_value()
    |> then(fn
      v when is_binary(v) -> v
      v -> inspect(v)
    end)
    |> relativize_in_text(session_cwd)
    |> truncate_preview(60)
  end

  defp tool_use_preview_enriched(_block, _session_cwd), do: ""

  @tool_preview_keys ~w(file_path path command pattern query url description prompt text)

  defp pick_tool_use_preview_value(input) do
    preferred =
      Enum.find_value(@tool_preview_keys, fn key ->
        case Map.get(input, key) do
          nil -> nil
          value -> value
        end
      end)

    preferred ||
      input
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.sort()
      |> List.first()
      |> then(fn
        nil -> ""
        first_key -> Map.get(input, first_key, "")
      end)
  end

  defp truncate_preview(text, limit) when is_binary(text) and is_integer(limit) and limit > 0 do
    if String.length(text) > limit do
      String.slice(text, 0, max(limit - 1, 0)) <> "…"
    else
      text
    end
  end

  defp truncate_preview(text, _limit), do: text

  # ── Subagent detection ─────────────────────────────────────────────

  defp put_subagent_ref(line_meta, msg) do
    ref = msg[:agent_id] || detect_subagent_in_text(line_meta.line)
    Map.put(line_meta, :subagent_ref, ref)
  end

  defp detect_subagent_in_text(text) when is_binary(text) do
    case Regex.run(@subagent_pattern, text) do
      [match] -> match
      _ -> nil
    end
  end

  defp detect_subagent_in_text(_text), do: nil

  # ── Enriched line builders ─────────────────────────────────────────

  defp plain_line(text, kind) do
    %{
      line: text,
      kind: kind,
      tool_use_id: nil,
      thread_key: nil,
      code_language: nil,
      render_mode: :plain,
      source_line_number: nil
    }
  end

  defp code_line(text, kind, language) do
    %{
      line: text,
      kind: kind,
      tool_use_id: nil,
      thread_key: nil,
      code_language: language,
      render_mode: :code,
      source_line_number: nil
    }
  end

  defp extract_thinking_text(%{"text" => text}), do: text

  defp extract_thinking_text(%{"blocks" => blocks}) when is_list(blocks) do
    blocks
    |> Enum.map(fn
      %{"type" => "thinking", "thinking" => t} -> t
      _ -> ""
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp extract_thinking_text(_content), do: ""

  # ── Legacy render_message helpers (unchanged) ──────────────────────

  defp extract_block_text(%{"type" => "text", "text" => text}), do: text
  defp extract_block_text(%{"type" => "tool_use", "name" => name}), do: "● #{name}"

  defp extract_block_text(%{"type" => "tool_result", "content" => content})
       when is_binary(content), do: content

  defp extract_block_text(_), do: ""

  defp render_assistant_content(%{"blocks" => blocks}) when is_list(blocks) do
    Enum.flat_map(blocks, &render_assistant_block/1)
  end

  defp render_assistant_content(%{"text" => text}) do
    String.split(text, "\n")
  end

  defp render_assistant_content(_), do: []

  defp render_assistant_block(%{"type" => "text", "text" => text}) do
    String.split(text, "\n")
  end

  defp render_assistant_block(%{"type" => "tool_use", "name" => name} = block) do
    preview = tool_use_preview(block)
    ["● #{name}(#{preview})"]
  end

  defp render_assistant_block(_), do: []

  defp render_user_content(%{"blocks" => blocks}) when is_list(blocks) do
    Enum.flat_map(blocks, &render_user_block/1)
  end

  defp render_user_content(%{"text" => text}) do
    String.split(text, "\n")
  end

  defp render_user_content(_), do: []

  defp render_user_block(%{"type" => "tool_result", "content" => content})
       when is_binary(content) do
    String.split(content, "\n")
  end

  defp render_user_block(%{"type" => "tool_result", "content" => content})
       when is_list(content) do
    Enum.flat_map(content, fn
      %{"type" => "text", "text" => text} -> String.split(text, "\n")
      _ -> []
    end)
  end

  defp render_user_block(%{"type" => "tool_result"}), do: ["(empty)"]

  defp render_user_block(%{"type" => "text", "text" => text}) do
    String.split(text, "\n")
  end

  defp render_user_block(_), do: []

  defp tool_use_preview(%{"input" => input}) when is_map(input) do
    input
    |> Map.values()
    |> List.first("")
    |> then(fn
      v when is_binary(v) -> v
      v -> inspect(v)
    end)
    |> String.slice(0, 60)
  end

  defp tool_use_preview(_), do: ""
end
