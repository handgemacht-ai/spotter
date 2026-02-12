defmodule Spotter.Transcripts.JsonlParser do
  @moduledoc """
  Parses Claude Code JSONL transcript files.
  """

  require Logger

  @doc """
  Parses a session transcript file.
  Returns `{:ok, map}` with session metadata and messages, or `{:error, reason}`.
  """
  @spec parse_session_file(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_session_file(path) do
    with {:ok, messages} <- parse_lines(path) do
      metadata = extract_session_metadata(messages)
      schema_version = detect_schema_version(messages)

      {:ok,
       %{
         session_id: metadata[:session_id],
         slug: metadata[:slug],
         cwd: metadata[:cwd],
         git_branch: metadata[:git_branch],
         version: metadata[:version],
         schema_version: schema_version,
         started_at: metadata[:started_at],
         ended_at: metadata[:ended_at],
         messages: messages
       }}
    end
  end

  @doc """
  Parses a subagent transcript file.
  Returns `{:ok, map}` with agent_id, metadata, and messages.
  """
  @spec parse_subagent_file(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_subagent_file(path) do
    agent_id = extract_agent_id(path)

    with {:ok, messages} <- parse_lines(path) do
      metadata = extract_session_metadata(messages)
      schema_version = detect_schema_version(messages)

      {:ok,
       %{
         agent_id: agent_id,
         session_id: metadata[:session_id],
         slug: metadata[:slug],
         cwd: metadata[:cwd],
         git_branch: metadata[:git_branch],
         version: metadata[:version],
         schema_version: schema_version,
         started_at: metadata[:started_at],
         ended_at: metadata[:ended_at],
         messages: messages
       }}
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

    # Phase 1: Collect pending file tool_use blocks from assistant messages
    pending_file_tools =
      messages
      |> Enum.reduce(%{}, fn msg, acc ->
        if msg[:type] in [:assistant, :tool_use] do
          collect_file_tool_uses(msg, acc)
        else
          acc
        end
      end)

    # Phase 2: Walk messages in order, match tool_results, build running aggregate
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

  # Private

  defp parse_lines(path) do
    if File.exists?(path) do
      messages =
        path
        |> File.stream!()
        |> Stream.map(&String.trim/1)
        |> Stream.reject(&(&1 == ""))
        |> Stream.map(&decode_line/1)
        |> Enum.reject(&is_nil/1)

      {:ok, messages}
    else
      {:error, :file_not_found}
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

  defp normalize_message(data) do
    %{
      uuid: data["uuid"],
      parent_uuid: data["parentUuid"],
      message_id: get_in(data, ["message", "id"]),
      type: parse_type(data["type"]),
      role: parse_role(get_in(data, ["message", "role"])),
      content: extract_content(data),
      raw_payload: data,
      timestamp: parse_timestamp(data["timestamp"]),
      is_sidechain: data["isSidechain"] == true,
      agent_id: data["agentId"],
      tool_use_id: data["toolUseId"],
      session_id: data["sessionId"],
      slug: data["slug"],
      cwd: data["cwd"],
      git_branch: data["gitBranch"],
      version: data["version"]
    }
  end

  defp extract_content(data) do
    content = get_in(data, ["message", "content"]) || data["content"]

    case content do
      nil -> nil
      c when is_binary(c) -> %{"text" => c}
      c when is_list(c) -> %{"blocks" => c}
      c when is_map(c) -> c
    end
  end

  defp parse_type(nil), do: :system
  defp parse_type("user"), do: :user
  defp parse_type("assistant"), do: :assistant
  defp parse_type("tool_use"), do: :tool_use
  defp parse_type("tool_result"), do: :tool_result
  defp parse_type("progress"), do: :progress
  defp parse_type("thinking"), do: :thinking
  defp parse_type("system"), do: :system
  defp parse_type("file_history_snapshot"), do: :file_history_snapshot
  defp parse_type("file-history-snapshot"), do: :file_history_snapshot
  defp parse_type(_), do: :system

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

  defp extract_session_metadata(messages) do
    # Session metadata is typically in the first few messages
    first_messages = Enum.take(messages, 10)

    %{
      session_id: find_field(first_messages, :session_id),
      slug: find_field(first_messages, :slug),
      cwd: find_field(first_messages, :cwd),
      git_branch: find_field(first_messages, :git_branch),
      version: find_field(first_messages, :version),
      started_at: first_non_nil_timestamp(messages),
      ended_at: last_non_nil_timestamp(messages)
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
    # Path like: .../subagents/agent-a78b257.jsonl
    path
    |> Path.basename(".jsonl")
    |> String.replace_prefix("agent-", "")
  end
end
