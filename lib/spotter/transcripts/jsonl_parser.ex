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
      started_at: List.first(messages)[:timestamp],
      ended_at: List.last(messages)[:timestamp]
    }
  end

  defp find_field(messages, field) do
    Enum.find_value(messages, fn msg -> msg[field] end)
  end

  defp extract_agent_id(path) do
    # Path like: .../subagents/agent-a78b257.jsonl
    path
    |> Path.basename(".jsonl")
    |> String.replace_prefix("agent-", "")
  end
end
