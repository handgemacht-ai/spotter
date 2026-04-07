defmodule Spotter.Transcripts.JsonlParser do
  @moduledoc """
  Parses Claude Code JSONL transcript files.

  ## Field exhaustiveness

  `normalize_message/1` consumes fields by popping them from a working copy of
  the decoded JSON. After all extractions, `check_unconsumed!/3` verifies
  nothing was left behind at each nesting level (top-level, message.*, usage.*).

  In dev/test an unconsumed field raises immediately so new Claude Code fields
  are never silently dropped. In prod it logs a warning.

  To handle a new field: add a `Map.pop` for it in `consume_top_level/1`,
  `consume_message/1`, or `consume_usage/1`.
  """

  require Logger

  @doc """
  Parses a session transcript file.
  Returns `{:ok, map}` with session metadata and messages, or `{:error, reason}`.
  """
  @spec parse_session_file(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_session_file(path) do
    with {:ok, messages} <- parse_lines(path, "main") do
      {:ok, build_parsed_result(messages)}
    end
  end

  @doc """
  Parses a subagent transcript file.
  Returns `{:ok, map}` with agent_id, metadata, and messages.
  """
  @spec parse_subagent_file(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_subagent_file(path) do
    agent_id = extract_agent_id(path)

    with {:ok, messages} <- parse_lines(path, "subagent:#{agent_id}") do
      {:ok, Map.put(build_parsed_result(messages), :agent_id, agent_id)}
    end
  end

  @doc """
  Detects schema version from message structure.
  Currently v1 only.
  """
  @spec detect_schema_version([map()]) :: integer()
  def detect_schema_version(_messages), do: 1

  @doc """
  Extracts session rework records from parsed messages.

  Rework is defined as the 2nd+ successful Write/Edit modification to the same file.
  Returns a list of rework record maps in transcript order.

  Options:
    - `:session_cwd` - working directory for relative path derivation
  """
  @spec extract_session_rework_records([map()], keyword()) :: [map()]
  def extract_session_rework_records(messages, opts \\ []) do
    session_cwd = Keyword.get(opts, :session_cwd)

    pending_file_tools =
      messages
      |> Enum.reduce(%{}, fn msg, acc ->
        if msg[:type] in [:assistant, :tool_use] do
          collect_file_tool_uses(msg, acc)
        else
          acc
        end
      end)

    initial_state = %{
      pending_file_tools: pending_file_tools,
      file_mod_counts: %{},
      first_tool_use_by_file: %{},
      rework_records: []
    }

    state =
      Enum.reduce(messages, initial_state, fn msg, state ->
        if msg[:type] in [:tool_result, :user] do
          process_tool_results(msg, state, session_cwd)
        else
          state
        end
      end)

    Enum.reverse(state.rework_records)
  end

  @doc "Returns `{normalized_atom, known?}` for a raw JSONL type string. Public for audit tooling."
  @spec classify_type(String.t() | nil) :: {atom(), boolean()}
  def classify_type(raw_type), do: parse_type_with_known(raw_type)

  # ---------------------------------------------------------------------------
  # Rework extraction helpers
  # ---------------------------------------------------------------------------

  defp collect_file_tool_uses(msg, acc) do
    blocks = get_content_blocks(msg[:content])

    Enum.reduce(blocks, acc, fn block, inner_acc ->
      with "tool_use" <- block["type"],
           name when name in ["Write", "Edit"] <- block["name"],
           id when is_binary(id) <- block["id"],
           file_path when is_binary(file_path) <- get_in(block, ["input", "file_path"]) do
        Map.put(inner_acc, id, %{
          tool_use_id: id,
          tool_name: name,
          file_path: file_path,
          timestamp: msg[:timestamp],
          message_uuid: msg[:uuid]
        })
      else
        _ -> inner_acc
      end
    end)
  end

  defp process_tool_results(msg, state, session_cwd) do
    msg[:content]
    |> get_content_blocks()
    |> Enum.reduce(state, fn block, st ->
      maybe_record_successful_tool_result(block, st, session_cwd)
    end)
  end

  defp maybe_record_successful_tool_result(block, state, session_cwd) do
    with "tool_result" <- block["type"],
         tool_use_id when is_binary(tool_use_id) <- block["tool_use_id"],
         false <- block["is_error"] == true,
         %{file_path: file_path} = tool_info <- Map.get(state.pending_file_tools, tool_use_id) do
      apply_successful_file_mod(state, tool_use_id, file_path, tool_info, session_cwd)
    else
      _ -> state
    end
  end

  defp apply_successful_file_mod(state, tool_use_id, file_path, tool_info, session_cwd) do
    file_key = compute_file_key(file_path, session_cwd)
    relative_path = compute_relative_path(file_path, session_cwd)

    new_count = Map.get(state.file_mod_counts, file_key, 0) + 1

    first_tool_use_by_file =
      Map.put_new(state.first_tool_use_by_file, file_key, tool_use_id)

    rework_records =
      if new_count >= 2 do
        record = %{
          tool_use_id: tool_use_id,
          file_path: file_path,
          relative_path: relative_path,
          occurrence_index: new_count,
          first_tool_use_id: Map.fetch!(first_tool_use_by_file, file_key),
          event_timestamp: tool_info.timestamp,
          detection_source: :transcript_sync
        }

        [record | state.rework_records]
      else
        state.rework_records
      end

    %{
      state
      | file_mod_counts: Map.put(state.file_mod_counts, file_key, new_count),
        first_tool_use_by_file: first_tool_use_by_file,
        rework_records: rework_records,
        pending_file_tools: Map.delete(state.pending_file_tools, tool_use_id)
    }
  end

  defp get_content_blocks(%{"blocks" => blocks}) when is_list(blocks), do: blocks
  defp get_content_blocks(content) when is_list(content), do: content
  defp get_content_blocks(_), do: []

  defp compute_file_key(file_path, nil), do: file_path

  defp compute_file_key(file_path, session_cwd) do
    if String.starts_with?(file_path, "/") do
      relative = Path.relative_to(file_path, session_cwd)
      if relative == file_path, do: file_path, else: relative
    else
      file_path
    end
  end

  defp compute_relative_path(_file_path, nil), do: nil

  defp compute_relative_path(file_path, session_cwd) do
    if String.starts_with?(file_path, "/") do
      relative = Path.relative_to(file_path, session_cwd)
      if relative == file_path, do: nil, else: relative
    else
      file_path
    end
  end

  # ---------------------------------------------------------------------------
  # Line parsing
  # ---------------------------------------------------------------------------

  defp parse_lines(path, source_scope) do
    if File.exists?(path) do
      messages =
        path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Stream.with_index()
        |> Stream.map(&decode_line_with_ordinal(&1, source_scope))
        |> Enum.reject(&is_nil/1)

      {:ok, messages}
    else
      {:error, :file_not_found}
    end
  end

  defp decode_line_with_ordinal({line, idx}, source_scope) do
    case decode_line(line) do
      nil -> nil
      msg -> Map.merge(msg, %{ordinal: idx, source_scope: source_scope})
    end
  end

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, data} ->
        normalize_message(data)

      {:error, _} ->
        Logger.warning("Skipping malformed JSONL line: #{String.slice(line, 0, 100)}")
        nil
    end
  end

  # ---------------------------------------------------------------------------
  # Message normalization — consume-by-popping
  #
  # Every field access pops the key from a working copy. After all extractions
  # the residual keys are checked. This means adding a new field to the parser
  # is just adding a Map.pop — forgetting triggers the exhaustiveness check.
  # ---------------------------------------------------------------------------

  defp normalize_message(original_data) do
    {fields, residual_top, residual_message, residual_usage} =
      consume_all_fields(original_data)

    raw_type = fields.raw_type
    {normalized_type, known?} = parse_type_with_known(raw_type)
    timestamp = parse_timestamp(fields.timestamp)
    {content, block_unconsumed} = normalize_content(fields.message_content, fields.top_content)

    check_unconsumed!("top-level", raw_type, residual_top)
    check_unconsumed!("message", raw_type, residual_message)
    check_unconsumed!("message.usage", raw_type, residual_usage)

    unconsumed =
      collect_unconsumed_paths(residual_top, residual_message, residual_usage, block_unconsumed)

    %{
      uuid: fields.uuid,
      parent_uuid: fields.parent_uuid,
      message_id: fields.message_id,
      type: normalized_type,
      role: parse_role(fields.message_role),
      content: content,
      raw_payload: original_data,
      timestamp: timestamp,
      is_sidechain: fields.is_sidechain == true,
      agent_id: fields.agent_id,
      tool_use_id: fields.tool_use_id,
      session_id: fields.session_id,
      slug: fields.slug,
      cwd: fields.cwd,
      git_branch: fields.git_branch,
      version: fields.version,
      team_name: fields.team_name,
      agent_name: fields.agent_name,
      record_type: raw_type,
      record_subtype: fields.subtype,
      normalization_status: normalization_status(known?, timestamp),
      parent_tool_use_id: fields.parent_tool_use_id,
      input_tokens: fields.input_tokens,
      output_tokens: fields.output_tokens,
      cache_read_input_tokens: fields.cache_read_input_tokens,
      cache_creation_input_tokens: fields.cache_creation_input_tokens,
      model: fields.message_model,
      is_meta: fields.is_meta == true,
      unconsumed_fields: unconsumed
    }
  end

  # Pop every known top-level, message, and usage field. Returns a flat
  # struct of extracted values plus the residual maps at each level.
  defp consume_all_fields(data) do
    # -- Top-level fields (common across types) --
    {raw_type, data} = Map.pop(data, "type")
    {uuid, data} = Map.pop(data, "uuid")
    {parent_uuid, data} = Map.pop(data, "parentUuid")
    {session_id, data} = Map.pop(data, "sessionId")
    {timestamp, data} = Map.pop(data, "timestamp")
    {is_sidechain, data} = Map.pop(data, "isSidechain")
    {agent_id, data} = Map.pop(data, "agentId")
    {agent_name, data} = Map.pop(data, "agentName")
    {team_name, data} = Map.pop(data, "teamName")
    {slug, data} = Map.pop(data, "slug")
    {cwd, data} = Map.pop(data, "cwd")
    {git_branch, data} = Map.pop(data, "gitBranch")
    {version, data} = Map.pop(data, "version")
    {subtype, data} = Map.pop(data, "subtype")

    # toolUseID: real data uses uppercase D, pop both casings
    {tool_use_id_upper, data} = Map.pop(data, "toolUseID")
    {tool_use_id_lower, data} = Map.pop(data, "toolUseId")
    tool_use_id = tool_use_id_upper || tool_use_id_lower

    # parentToolUseID: same dual-casing
    {parent_tool_use_id_upper, data} = Map.pop(data, "parentToolUseID")
    {parent_tool_use_id_lower, data} = Map.pop(data, "parentToolUseId")
    parent_tool_use_id = parent_tool_use_id_upper || parent_tool_use_id_lower

    # -- Top-level fields (type-specific, consumed but stored in raw_payload) --
    # "role" appears at top-level in some older/test records (redundant with message.role)
    {_top_role, data} = Map.pop(data, "role")
    {_entrypoint, data} = Map.pop(data, "entrypoint")
    {_user_type, data} = Map.pop(data, "userType")
    {_request_id, data} = Map.pop(data, "requestId")
    {_error, data} = Map.pop(data, "error")
    {_api_error, data} = Map.pop(data, "apiError")
    {_is_api_error, data} = Map.pop(data, "isApiErrorMessage")
    {_permission_mode, data} = Map.pop(data, "permissionMode")
    {_is_compact_summary, data} = Map.pop(data, "isCompactSummary")
    {is_meta, data} = Map.pop(data, "isMeta")
    {_is_visible_transcript, data} = Map.pop(data, "isVisibleInTranscriptOnly")
    {_origin, data} = Map.pop(data, "origin")
    {_plan_content, data} = Map.pop(data, "planContent")
    {_prompt_id, data} = Map.pop(data, "promptId")
    {_source_tool_assistant_uuid, data} = Map.pop(data, "sourceToolAssistantUUID")
    {_source_tool_use_id, data} = Map.pop(data, "sourceToolUseID")
    {_thinking_metadata, data} = Map.pop(data, "thinkingMetadata")
    {_todos, data} = Map.pop(data, "todos")
    {_tool_use_result, data} = Map.pop(data, "toolUseResult")
    {_data_payload, data} = Map.pop(data, "data")
    {_level, data} = Map.pop(data, "level")
    {_cause, data} = Map.pop(data, "cause")
    {_compact_metadata, data} = Map.pop(data, "compactMetadata")
    {_duration_ms, data} = Map.pop(data, "durationMs")
    {_has_output, data} = Map.pop(data, "hasOutput")
    {_hook_count, data} = Map.pop(data, "hookCount")
    {_hook_errors, data} = Map.pop(data, "hookErrors")
    {_hook_infos, data} = Map.pop(data, "hookInfos")
    {_logical_parent_uuid, data} = Map.pop(data, "logicalParentUuid")
    {_max_retries, data} = Map.pop(data, "maxRetries")
    {_message_count, data} = Map.pop(data, "messageCount")
    {_prevented_continuation, data} = Map.pop(data, "preventedContinuation")
    {_retry_attempt, data} = Map.pop(data, "retryAttempt")
    {_retry_in_ms, data} = Map.pop(data, "retryInMs")
    {_stop_reason, data} = Map.pop(data, "stopReason")
    {_url, data} = Map.pop(data, "url")
    {_verb, data} = Map.pop(data, "verb")
    {_written_paths, data} = Map.pop(data, "writtenPaths")
    {_operation, data} = Map.pop(data, "operation")
    {_message_id_fhs, data} = Map.pop(data, "messageId")
    {_snapshot, data} = Map.pop(data, "snapshot")
    {_is_snapshot_update, data} = Map.pop(data, "isSnapshotUpdate")
    {_last_prompt, data} = Map.pop(data, "lastPrompt")
    {_attachment, data} = Map.pop(data, "attachment")
    {_custom_title, data} = Map.pop(data, "customTitle")
    {_worktree_session, data} = Map.pop(data, "worktreeSession")
    {_pr_number, data} = Map.pop(data, "prNumber")
    {_pr_repository, data} = Map.pop(data, "prRepository")
    {_pr_url, data} = Map.pop(data, "prUrl")

    # -- Top-level "content" (used by system, queue-operation, thinking) --
    {top_content, data} = Map.pop(data, "content")

    # -- Nested: message object --
    {message_map, data} = Map.pop(data, "message")

    {message_id, message_role, message_content, message_model, residual_message, residual_usage,
     usage_tokens} =
      consume_message(message_map)

    fields = %{
      raw_type: raw_type,
      uuid: uuid,
      parent_uuid: parent_uuid,
      session_id: session_id,
      timestamp: timestamp,
      is_sidechain: is_sidechain,
      agent_id: agent_id,
      agent_name: agent_name,
      team_name: team_name,
      slug: slug,
      cwd: cwd,
      git_branch: git_branch,
      version: version,
      subtype: subtype,
      tool_use_id: tool_use_id,
      parent_tool_use_id: parent_tool_use_id,
      message_id: message_id,
      message_role: message_role,
      message_content: message_content,
      message_model: message_model,
      top_content: top_content,
      input_tokens: usage_tokens.input_tokens,
      output_tokens: usage_tokens.output_tokens,
      cache_read_input_tokens: usage_tokens.cache_read_input_tokens,
      cache_creation_input_tokens: usage_tokens.cache_creation_input_tokens,
      is_meta: is_meta
    }

    {fields, data, residual_message, residual_usage}
  end

  defp consume_message(nil) do
    {nil, nil, nil, nil, %{}, :no_message,
     %{
       input_tokens: nil,
       output_tokens: nil,
       cache_read_input_tokens: nil,
       cache_creation_input_tokens: nil
     }}
  end

  defp consume_message(message) when is_map(message) do
    {msg_id, message} = Map.pop(message, "id")
    {msg_role, message} = Map.pop(message, "role")
    {msg_content, message} = Map.pop(message, "content")
    {msg_model, message} = Map.pop(message, "model")
    {_msg_type, message} = Map.pop(message, "type")
    {_stop_reason, message} = Map.pop(message, "stop_reason")
    {_stop_sequence, message} = Map.pop(message, "stop_sequence")
    {_stop_details, message} = Map.pop(message, "stop_details")
    {_container, message} = Map.pop(message, "container")
    {_context_management, message} = Map.pop(message, "context_management")

    {usage_map, message} = Map.pop(message, "usage")
    {residual_usage, usage_tokens} = consume_usage(usage_map)

    {msg_id, msg_role, msg_content, msg_model, message, residual_usage, usage_tokens}
  end

  defp consume_message(_other) do
    {nil, nil, nil, nil, %{}, :no_message,
     %{
       input_tokens: nil,
       output_tokens: nil,
       cache_read_input_tokens: nil,
       cache_creation_input_tokens: nil
     }}
  end

  defp consume_usage(nil) do
    {%{},
     %{
       input_tokens: nil,
       output_tokens: nil,
       cache_read_input_tokens: nil,
       cache_creation_input_tokens: nil
     }}
  end

  defp consume_usage(usage) when is_map(usage) do
    {input_tokens, usage} = Map.pop(usage, "input_tokens")
    {output_tokens, usage} = Map.pop(usage, "output_tokens")
    {cache_read, usage} = Map.pop(usage, "cache_read_input_tokens")
    {cache_creation, usage} = Map.pop(usage, "cache_creation_input_tokens")
    {_cache_creation_flag, usage} = Map.pop(usage, "cache_creation")
    {_server_tool_use, usage} = Map.pop(usage, "server_tool_use")
    {_service_tier, usage} = Map.pop(usage, "service_tier")
    {_speed, usage} = Map.pop(usage, "speed")
    {_iterations, usage} = Map.pop(usage, "iterations")
    {_inference_geo, usage} = Map.pop(usage, "inference_geo")

    tokens = %{
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      cache_read_input_tokens: cache_read,
      cache_creation_input_tokens: cache_creation
    }

    {usage, tokens}
  end

  defp consume_usage(_other) do
    {%{},
     %{
       input_tokens: nil,
       output_tokens: nil,
       cache_read_input_tokens: nil,
       cache_creation_input_tokens: nil
     }}
  end

  # ---------------------------------------------------------------------------
  # Unconsumed field detection
  # ---------------------------------------------------------------------------

  defp check_unconsumed!(_level, _raw_type, residual) when residual == %{}, do: :ok
  defp check_unconsumed!(_level, _raw_type, :no_message), do: :ok

  defp check_unconsumed!(level, raw_type, residual) when map_size(residual) > 0 do
    keys = Map.keys(residual) |> Enum.sort() |> Enum.join(", ")

    if Mix.env() in [:dev, :test] do
      raise "Unconsumed JSONL fields at #{level} for type=#{raw_type}: #{keys}"
    else
      Logger.warning("Unconsumed JSONL fields at #{level} for type=#{raw_type}: #{keys}")
    end
  end

  defp collect_unconsumed_paths(residual_top, residual_message, residual_usage, block_unconsumed) do
    top = Map.keys(residual_top) |> Enum.map(&"#{&1}")

    msg =
      if residual_message == :no_message,
        do: [],
        else: Map.keys(residual_message) |> Enum.map(&"message.#{&1}")

    usg =
      if residual_usage == :no_message,
        do: [],
        else: Map.keys(residual_usage) |> Enum.map(&"message.usage.#{&1}")

    case top ++ msg ++ usg ++ block_unconsumed do
      [] -> nil
      paths -> paths
    end
  end

  # ---------------------------------------------------------------------------
  # Content normalization
  # ---------------------------------------------------------------------------

  defp normalize_content(message_content, top_content) do
    content = message_content || top_content

    case content do
      nil ->
        {nil, []}

      c when is_binary(c) ->
        {%{"text" => c}, []}

      c when is_list(c) ->
        block_unconsumed =
          c
          |> Enum.with_index()
          |> Enum.flat_map(fn {block, idx} -> validate_content_block(block, idx) end)

        {%{"blocks" => c}, block_unconsumed}

      c when is_map(c) ->
        {c, []}
    end
  end

  # ---------------------------------------------------------------------------
  # Content block validation — consume-by-popping per block type
  #
  # Each block type has known fields that are popped from a working copy.
  # Residual keys are checked via check_unconsumed!/3. The original block
  # is NOT modified — validation is a side effect only.
  # ---------------------------------------------------------------------------

  defp validate_content_block(block, idx) when is_map(block) do
    {block_type, working} = Map.pop(block, "type")

    residual =
      case block_type do
        "text" -> consume_text_block(working)
        "thinking" -> consume_thinking_block(working)
        "tool_use" -> consume_tool_use_block(working)
        "tool_result" -> consume_tool_result_block(working)
        other -> warn_unknown_block_type(other, idx)
      end

    check_unconsumed!("content_block[#{block_type}]", block_type, residual)

    residual
    |> Map.keys()
    |> Enum.map(&"content.blocks[#{idx}].#{&1}")
  end

  defp validate_content_block(_non_map, _idx), do: []

  defp consume_text_block(working) do
    {_text, working} = Map.pop(working, "text")
    working
  end

  defp consume_thinking_block(working) do
    {_thinking, working} = Map.pop(working, "thinking")
    {_signature, working} = Map.pop(working, "signature")
    working
  end

  defp consume_tool_use_block(working) do
    {_id, working} = Map.pop(working, "id")
    {_name, working} = Map.pop(working, "name")
    {_input, working} = Map.pop(working, "input")
    {_caller, working} = Map.pop(working, "caller")
    working
  end

  defp consume_tool_result_block(working) do
    {_tool_use_id, working} = Map.pop(working, "tool_use_id")
    {_is_error, working} = Map.pop(working, "is_error")
    {_content, working} = Map.pop(working, "content")
    working
  end

  defp warn_unknown_block_type(block_type, idx) do
    Logger.warning("Unknown content block type at index #{idx}: #{inspect(block_type)}")
    %{}
  end

  # ---------------------------------------------------------------------------
  # Type classification
  # ---------------------------------------------------------------------------

  defp parse_type_with_known(nil), do: {:system, true}
  defp parse_type_with_known("user"), do: {:user, true}
  defp parse_type_with_known("human"), do: {:user, true}
  defp parse_type_with_known("assistant"), do: {:assistant, true}
  defp parse_type_with_known("tool_use"), do: {:tool_use, true}
  defp parse_type_with_known("tool_result"), do: {:tool_result, true}
  defp parse_type_with_known("result"), do: {:tool_result, true}
  defp parse_type_with_known("progress"), do: {:progress, true}
  defp parse_type_with_known("thinking"), do: {:thinking, true}
  defp parse_type_with_known("system"), do: {:system, true}
  defp parse_type_with_known("file_history_snapshot"), do: {:file_history_snapshot, true}
  defp parse_type_with_known("file-history-snapshot"), do: {:file_history_snapshot, true}
  defp parse_type_with_known("queue-operation"), do: {:queue_operation, true}
  defp parse_type_with_known("last-prompt"), do: {:last_prompt, true}
  defp parse_type_with_known("attachment"), do: {:attachment, true}
  defp parse_type_with_known("permission-mode"), do: {:permission_mode, true}
  defp parse_type_with_known("custom-title"), do: {:custom_title, true}
  defp parse_type_with_known("agent-name"), do: {:agent_name, true}
  defp parse_type_with_known("worktree-state"), do: {:worktree_state, true}
  defp parse_type_with_known("pr-link"), do: {:pr_link, true}
  defp parse_type_with_known(_), do: {:system, false}

  defp normalization_status(true, %DateTime{}), do: :full
  defp normalization_status(true, _nil_ts), do: :partial
  defp normalization_status(false, _), do: :raw_only

  defp parse_role(nil), do: nil
  defp parse_role("user"), do: :user
  defp parse_role("assistant"), do: :assistant
  defp parse_role("system"), do: :system
  defp parse_role(_), do: nil

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_timestamp(_), do: nil

  # ---------------------------------------------------------------------------
  # Session metadata
  # ---------------------------------------------------------------------------

  defp build_parsed_result(messages) do
    metadata = extract_session_metadata(messages)

    %{
      session_id: metadata[:session_id],
      slug: metadata[:slug],
      cwd: metadata[:cwd],
      git_branch: metadata[:git_branch],
      version: metadata[:version],
      schema_version: detect_schema_version(messages),
      started_at: metadata[:started_at],
      ended_at: metadata[:ended_at],
      messages: messages,
      team_name: metadata[:team_name],
      agent_name: metadata[:agent_name]
    }
  end

  defp extract_session_metadata(messages) do
    first_messages = Enum.take(messages, 10)

    %{
      session_id: find_field(first_messages, :session_id),
      slug: find_field(first_messages, :slug),
      cwd: find_field(first_messages, :cwd),
      git_branch: find_field(first_messages, :git_branch),
      version: find_field(first_messages, :version),
      started_at: first_non_nil_timestamp(messages),
      ended_at: last_non_nil_timestamp(messages),
      team_name: find_field(first_messages, :team_name),
      agent_name: find_field(first_messages, :agent_name)
    }
  end

  defp find_field(messages, field) do
    Enum.find_value(messages, fn msg -> msg[field] end)
  end

  defp first_non_nil_timestamp(messages) do
    Enum.find_value(messages, fn msg -> msg[:timestamp] end)
  end

  defp last_non_nil_timestamp(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn msg -> msg[:timestamp] end)
  end

  defp extract_agent_id(path) do
    path
    |> Path.basename(".jsonl")
    |> String.replace_prefix("agent-", "")
  end
end
