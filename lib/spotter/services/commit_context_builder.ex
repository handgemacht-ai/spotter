defmodule Spotter.Services.CommitContextBuilder do
  @moduledoc "Builds stable, merged context windows around changed code ranges."

  @default_context_lines 80
  @default_max_window_lines 200
  @default_max_window_bytes 20_000
  @truncation_marker "\n... (truncated)\n"

  @doc """
  Builds merged context windows from a list of changed ranges within a file.

  Each range is `{line_start, line_end}`. Windows are expanded by `context_lines`
  (default 80, env `SPOTTER_COMMIT_CONTEXT_LINES`), clamped to file bounds, and merged
  when overlapping.

  Oversized windows are split by `max_window_lines` (default 200) and content is
  truncated to `max_window_bytes` (default 20000).

  Returns a list of `%{line_start: integer, line_end: integer, content: String.t()}`.
  """
  @spec build_windows(String.t(), [{integer(), integer()}], keyword()) :: [map()]
  def build_windows(file_content, ranges, opts \\ [])
  def build_windows("", _ranges, _opts), do: []

  def build_windows(file_content, ranges, opts) do
    all_lines = String.split(file_content, "\n")
    max_line = length(all_lines)

    if max_line == 0 do
      []
    else
      do_build_windows(all_lines, max_line, ranges, opts)
    end
  end

  defp do_build_windows(all_lines, max_line, ranges, opts) do
    context_lines = Keyword.get(opts, :context_lines, context_lines_setting())
    max_window_lines = Keyword.get(opts, :max_window_lines, max_window_lines_setting())
    max_window_bytes = Keyword.get(opts, :max_window_bytes, max_window_bytes_setting())

    ranges
    |> Enum.sort()
    |> Enum.map(fn {line_start, line_end} ->
      {max(1, line_start - context_lines), min(max_line, line_end + context_lines)}
    end)
    |> merge_overlapping()
    |> Enum.flat_map(&split_window(&1, max_window_lines))
    |> Enum.map(&window_to_map(all_lines, &1, max_window_bytes))
  end

  defp window_to_map(all_lines, {ws, we}, max_window_bytes) do
    content =
      all_lines
      |> Enum.slice((ws - 1)..(we - 1)//1)
      |> Enum.with_index(ws)
      |> Enum.map_join("\n", fn {line, num} -> "#{num}: #{line}" end)
      |> truncate_bytes(max_window_bytes)

    %{line_start: ws, line_end: we, content: content}
  end

  defp split_window({ws, we}, max_lines) when we - ws + 1 <= max_lines, do: [{ws, we}]

  defp split_window({ws, we}, max_lines) do
    ws
    |> Stream.unfold(&split_next(&1, we, max_lines))
    |> Enum.to_list()
  end

  defp split_next(start, _we, _max_lines) when start == :done, do: nil

  defp split_next(start, we, max_lines) do
    chunk_end = min(start + max_lines - 1, we)
    next = if chunk_end >= we, do: :done, else: chunk_end + 1
    {{start, chunk_end}, next}
  end

  defp truncate_bytes(content, max_bytes) when byte_size(content) <= max_bytes, do: content

  defp truncate_bytes(content, max_bytes) do
    marker_bytes = byte_size(@truncation_marker)
    available = max(0, max_bytes - marker_bytes)
    truncated = safe_binary_slice(content, available)
    truncated <> @truncation_marker
  end

  defp safe_binary_slice(binary, max_bytes) do
    sliced = binary_part(binary, 0, min(max_bytes, byte_size(binary)))

    if String.valid?(sliced) do
      sliced
    else
      trim_to_valid_utf8(binary, max_bytes - 1)
    end
  end

  defp trim_to_valid_utf8(_binary, len) when len <= 0, do: ""

  defp trim_to_valid_utf8(binary, len) do
    candidate = binary_part(binary, 0, len)

    if String.valid?(candidate) do
      candidate
    else
      trim_to_valid_utf8(binary, len - 1)
    end
  end

  defp merge_overlapping([]), do: []

  defp merge_overlapping([first | rest]) do
    Enum.reduce(rest, [first], fn {s, e}, [{cs, ce} | acc] ->
      if s <= ce + 1 do
        [{cs, max(ce, e)} | acc]
      else
        [{s, e}, {cs, ce} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp context_lines_setting do
    env_int("SPOTTER_COMMIT_CONTEXT_LINES", @default_context_lines)
  end

  defp max_window_lines_setting do
    env_int("SPOTTER_COMMIT_MAX_WINDOW_LINES", @default_max_window_lines)
  end

  defp max_window_bytes_setting do
    env_int("SPOTTER_COMMIT_MAX_WINDOW_BYTES", @default_max_window_bytes)
  end

  defp env_int(var, default) do
    case System.get_env(var) do
      nil -> default
      val -> String.to_integer(val)
    end
  end
end
