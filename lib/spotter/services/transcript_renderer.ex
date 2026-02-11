defmodule Spotter.Services.TranscriptRenderer do
  @moduledoc """
  Pseudo-renders Claude Code transcript messages into displayable text lines.

  Converts parsed JSONL messages into a flat list of line maps that approximate
  what Claude Code renders in the terminal.
  """

  @max_result_lines 5

  @doc """
  Renders a list of parsed messages into line maps.

  Returns a list of `%{line: string, message_id: string, type: atom, line_number: integer}`.
  """
  @spec render([map()]) :: [map()]
  def render(messages) do
    messages
    |> Enum.flat_map(fn msg ->
      msg
      |> render_message()
      |> Enum.map(fn line -> %{line: line, message_id: msg[:uuid], type: msg[:type]} end)
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

  # Private

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
