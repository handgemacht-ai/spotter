defmodule Spotter.Services.TranscriptRenderer do
  @moduledoc """
  Pseudo-renders Claude Code transcript messages into displayable text lines.

  Converts parsed JSONL messages into a flat list of line maps that approximate
  what Claude Code renders in the terminal.
  """

  @max_result_lines 5
  @subagent_pattern ~r/agent-[a-zA-Z0-9]+/

  @doc """
  Renders a list of parsed messages into enriched line maps.

  Each line map contains `:line`, `:message_id`, `:type`, `:line_number`,
  `:kind`, `:tool_use_id`, `:thread_key`, `:subagent_ref`, `:code_language`,
  and `:render_mode`.

  ## Options

    * `:session_cwd` - Session working directory for relativizing file paths.

  """
  @spec render([map()], keyword()) :: [map()]
  def render(messages, opts \\ []) do
    session_cwd = opts[:session_cwd]

    messages
    |> Enum.flat_map(fn msg ->
      msg
      |> render_message_enriched(session_cwd)
      |> Enum.map(fn line_meta ->
        line_meta
        |> Map.put(:message_id, msg[:uuid])
        |> Map.put(:type, msg[:type])
        |> put_subagent_ref(msg)
      end)
    end)
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

  # ── Enriched rendering (used by render/2) ──────────────────────────

  defp render_message_enriched(%{type: type}, _session_cwd)
       when type in [:progress, :system, :file_history_snapshot] do
    []
  end

  defp render_message_enriched(%{content: nil}, _session_cwd), do: []

  defp render_message_enriched(%{type: :thinking, content: content}, _session_cwd) do
    content
    |> extract_thinking_text()
    |> String.split("\n")
    |> Enum.map(&plain_line(&1, :thinking))
  end

  defp render_message_enriched(%{type: :assistant, content: content}, session_cwd) do
    render_assistant_content_enriched(content, session_cwd)
  end

  defp render_message_enriched(%{type: :user, content: content}, session_cwd) do
    render_user_content_enriched(content, session_cwd)
  end

  defp render_message_enriched(_msg, _session_cwd), do: []

  # ── Enriched assistant rendering ───────────────────────────────────

  defp render_assistant_content_enriched(%{"blocks" => blocks}, session_cwd)
       when is_list(blocks) do
    Enum.flat_map(blocks, &render_assistant_block_enriched(&1, session_cwd))
  end

  defp render_assistant_content_enriched(%{"text" => text}, _session_cwd) do
    classify_text_lines(String.split(text, "\n"), :text)
  end

  defp render_assistant_content_enriched(_content, _session_cwd), do: []

  defp render_assistant_block_enriched(%{"type" => "text", "text" => text}, _session_cwd) do
    classify_text_lines(String.split(text, "\n"), :text)
  end

  defp render_assistant_block_enriched(%{"type" => "thinking", "thinking" => text}, _session_cwd) do
    text
    |> String.split("\n")
    |> Enum.map(&plain_line(&1, :thinking))
  end

  defp render_assistant_block_enriched(
         %{"type" => "tool_use", "name" => name} = block,
         session_cwd
       ) do
    preview = tool_use_preview_enriched(block, session_cwd)
    tool_id = block["id"]
    thread_key = tool_id || "tool-use-#{name}"

    [
      %{
        line: "● #{name}(#{preview})",
        kind: :tool_use,
        tool_use_id: tool_id,
        thread_key: thread_key,
        code_language: nil,
        render_mode: :plain
      }
    ]
  end

  defp render_assistant_block_enriched(_block, _session_cwd), do: []

  # ── Enriched user rendering ────────────────────────────────────────

  defp render_user_content_enriched(%{"blocks" => blocks}, session_cwd)
       when is_list(blocks) do
    Enum.flat_map(blocks, &render_user_block_enriched(&1, session_cwd))
  end

  defp render_user_content_enriched(%{"text" => text}, _session_cwd) do
    classify_text_lines(String.split(text, "\n"), :text)
  end

  defp render_user_content_enriched(_content, _session_cwd), do: []

  defp render_user_block_enriched(
         %{"type" => "tool_result", "content" => content} = block,
         session_cwd
       )
       when is_binary(content) do
    tool_use_id = block["tool_use_id"]
    thread_key = tool_use_id || "unmatched-result"

    content
    |> String.split("\n")
    |> Enum.take(@max_result_lines)
    |> Enum.map(fn line ->
      %{
        line: "  ⎿  #{relativize_in_text(line, session_cwd)}",
        kind: :tool_result,
        tool_use_id: tool_use_id,
        thread_key: thread_key,
        code_language: nil,
        render_mode: :plain
      }
    end)
  end

  defp render_user_block_enriched(
         %{"type" => "tool_result", "content" => content} = block,
         session_cwd
       )
       when is_list(content) do
    tool_use_id = block["tool_use_id"]
    thread_key = tool_use_id || "unmatched-result"

    content
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => text} -> String.split(text, "\n")
      _ -> []
    end)
    |> Enum.take(@max_result_lines)
    |> Enum.map(fn line ->
      %{
        line: "  ⎿  #{relativize_in_text(line, session_cwd)}",
        kind: :tool_result,
        tool_use_id: tool_use_id,
        thread_key: thread_key,
        code_language: nil,
        render_mode: :plain
      }
    end)
  end

  defp render_user_block_enriched(%{"type" => "tool_result"} = block, _session_cwd) do
    tool_use_id = block["tool_use_id"]
    thread_key = tool_use_id || "unmatched-result"

    [
      %{
        line: "  ⎿  (empty)",
        kind: :tool_result,
        tool_use_id: tool_use_id,
        thread_key: thread_key,
        code_language: nil,
        render_mode: :plain
      }
    ]
  end

  defp render_user_block_enriched(%{"type" => "text", "text" => text}, _session_cwd) do
    classify_text_lines(String.split(text, "\n"), :text)
  end

  defp render_user_block_enriched(_block, _session_cwd), do: []

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
    |> Map.values()
    |> List.first("")
    |> then(fn
      v when is_binary(v) -> v
      v -> inspect(v)
    end)
    |> String.slice(0, 60)
    |> relativize_in_text(session_cwd)
  end

  defp tool_use_preview_enriched(_block, _session_cwd), do: ""

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
      render_mode: :plain
    }
  end

  defp code_line(text, kind, language) do
    %{
      line: text,
      kind: kind,
      tool_use_id: nil,
      thread_key: nil,
      code_language: language,
      render_mode: :code
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
    content
    |> String.split("\n")
    |> Enum.take(@max_result_lines)
    |> Enum.map(&"  ⎿  #{&1}")
  end

  defp render_user_block(%{"type" => "tool_result", "content" => content})
       when is_list(content) do
    content
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => text} -> String.split(text, "\n")
      _ -> []
    end)
    |> Enum.take(@max_result_lines)
    |> Enum.map(&"  ⎿  #{&1}")
  end

  defp render_user_block(%{"type" => "tool_result"}), do: ["  ⎿  (empty)"]

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
