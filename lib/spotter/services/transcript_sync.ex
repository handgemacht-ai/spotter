defmodule Spotter.Services.TranscriptSync do
  @moduledoc """
  Precomputes a breakpoint map for transcript-terminal scroll sync.

  Walks rendered transcript lines and terminal capture output to find anchor points
  where transcript content can be reliably identified in terminal output, then
  interpolates between anchors to produce a sorted breakpoint map.

  The breakpoint map is a list of `%{t: terminal_line, id: message_id}` entries
  that the client uses for instant binary-search scroll sync with zero server roundtrips.
  """

  alias Spotter.Services.{TmuxOutput, TranscriptRenderer}

  @max_lookahead 50

  @doc """
  Builds a breakpoint map from rendered transcript lines and raw terminal capture.

  Returns a sorted list of `%{t: integer, id: String.t()}` where `t` is a 0-based
  terminal line index and `id` is a message_id. Only boundary transitions are included.
  """
  @spec build_breakpoint_map([map()], String.t()) :: [map()]
  def build_breakpoint_map([], _terminal_capture), do: []
  def build_breakpoint_map(_rendered_lines, ""), do: []
  def build_breakpoint_map(_rendered_lines, nil), do: []

  def build_breakpoint_map(rendered_lines, terminal_capture) do
    terminal_lines = prepare_terminal_lines(terminal_capture)
    anchors = find_anchors(rendered_lines, terminal_lines)
    interpolate(anchors, length(terminal_lines))
  end

  @doc """
  Prepares terminal capture text into cleaned lines for matching.

  Strips ANSI escape codes and trailing whitespace, then splits on newlines.
  """
  @spec prepare_terminal_lines(String.t()) :: [String.t()]
  def prepare_terminal_lines(nil), do: []
  def prepare_terminal_lines(""), do: []

  def prepare_terminal_lines(terminal_capture) do
    terminal_capture
    |> TranscriptRenderer.strip_ansi()
    |> TmuxOutput.strip_trailing_spaces()
    |> String.split("\n")
  end

  @doc """
  Finds anchor points where transcript lines match terminal lines.

  Uses a forward-only consume cursor with max lookahead of #{@max_lookahead} lines.
  Returns sorted list of `%{t: integer, tl: integer, id: String.t(), type: atom}`.
  """
  @spec find_anchors([map()], [String.t()]) :: [map()]
  def find_anchors([], _terminal_lines), do: []
  def find_anchors(_rendered_lines, []), do: []

  def find_anchors(rendered_lines, terminal_lines) do
    terminal_array = :array.from_list(terminal_lines)
    terminal_size = :array.size(terminal_array)

    rendered_lines
    |> Enum.reduce({[], 0}, &reduce_anchors(&1, &2, terminal_array, terminal_size))
    |> elem(0)
    |> Enum.reverse()
  end

  @doc """
  Interpolates between anchors to fill gaps proportionally.

  Returns a deduplicated breakpoint list where only message_id transitions are kept.
  """
  @spec interpolate([map()], non_neg_integer()) :: [map()]
  def interpolate([], _total_terminal_lines), do: []
  def interpolate(_anchors, 0), do: []

  def interpolate([single], _total_terminal_lines) do
    [%{t: 0, id: single.id}]
  end

  def interpolate(anchors, total_terminal_lines) do
    first = List.first(anchors)
    last = List.last(anchors)

    before = if first.t > 0, do: [%{t: 0, id: first.id}], else: []
    anchor_entries = Enum.map(anchors, fn a -> %{t: a.t, id: a.id} end)

    between =
      anchors
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [a1, a2] -> interpolate_pair(a1, a2) end)

    after_last =
      if last.t < total_terminal_lines - 1,
        do: [%{t: last.t + 1, id: last.id}],
        else: []

    (before ++ anchor_entries ++ between ++ after_last)
    |> Enum.sort_by(& &1.t)
    |> Enum.dedup_by(& &1.t)
    |> deduplicate_consecutive_ids()
  end

  # Private — anchor reduction

  defp reduce_anchors(_rendered_line, {anchors, cursor}, _array, size) when cursor >= size do
    {anchors, cursor}
  end

  defp reduce_anchors(rendered_line, {anchors, cursor}, array, size) do
    end_idx = min(cursor + @max_lookahead - 1, size - 1)

    case try_match(rendered_line, array, cursor, end_idx) do
      {:match, t, type} ->
        anchor = %{t: t, tl: rendered_line.line_number, id: rendered_line.message_id, type: type}
        {[anchor | anchors], t + 1}

      :no_match ->
        {anchors, cursor}
    end
  end

  defp try_match(rendered_line, terminal_array, cursor, end_idx) do
    trimmed = String.trim(rendered_line.line)

    if trimmed == "" do
      :no_match
    else
      classify_and_scan(rendered_line.type, trimmed, terminal_array, cursor, end_idx)
    end
  end

  # Match classification — each strategy is a separate function head

  defp classify_and_scan(:assistant, "●" <> _ = trimmed, array, cursor, end_idx) do
    tool_name = extract_tool_name(trimmed)

    scan_for(array, cursor, end_idx, :tool_use, fn tline ->
      String.contains?(tline, "●") and String.contains?(tline, tool_name)
    end)
  end

  defp classify_and_scan(:user, "⎿" <> _ = trimmed, array, cursor, end_idx) do
    try_result_match(trimmed, array, cursor, end_idx)
  end

  defp classify_and_scan(:user, trimmed, array, cursor, end_idx) do
    if String.length(trimmed) > 10 do
      needle = String.slice(trimmed, 0, 40)
      scan_for(array, cursor, end_idx, :user, &String.contains?(&1, needle))
    else
      :no_match
    end
  end

  defp classify_and_scan(:assistant, trimmed, array, cursor, end_idx) do
    if String.length(trimmed) > 30 do
      needle = String.slice(trimmed, 0, 30)
      scan_for(array, cursor, end_idx, :text, &String.contains?(&1, needle))
    else
      :no_match
    end
  end

  defp classify_and_scan(_type, _trimmed, _array, _cursor, _end_idx), do: :no_match

  defp try_result_match(trimmed, array, cursor, end_idx) do
    content_after = trimmed |> String.replace_leading("⎿", "") |> String.trim()
    needle = String.slice(content_after, 0, 30)

    if String.length(needle) > 5 do
      scan_for(array, cursor, end_idx, :result, fn tline ->
        String.contains?(tline, "⎿") and String.contains?(tline, needle)
      end)
    else
      :no_match
    end
  end

  defp scan_for(terminal_array, from, to, type, match_fn) do
    case Enum.find(from..to//1, fn idx -> match_fn.(:array.get(idx, terminal_array)) end) do
      nil -> :no_match
      t -> {:match, t, type}
    end
  end

  defp extract_tool_name(trimmed) do
    trimmed
    |> String.replace_leading("● ", "")
    |> String.split("(", parts: 2)
    |> List.first("")
    |> String.trim()
  end

  # Private — interpolation

  defp interpolate_pair(%{id: id}, %{id: id}), do: []

  defp interpolate_pair(a1, a2) do
    t_gap = a2.t - a1.t
    if t_gap <= 1, do: [], else: fill_gap(a1, a2, t_gap)
  end

  defp fill_gap(a1, a2, t_gap) do
    midpoint = a1.t + div(t_gap, 2)

    Enum.map((a1.t + 1)..(a2.t - 1)//1, fn t ->
      %{t: t, id: if(t <= midpoint, do: a1.id, else: a2.id)}
    end)
  end

  defp deduplicate_consecutive_ids(entries) do
    entries
    |> Enum.reduce([], fn entry, acc ->
      case acc do
        [prev | _] when prev.id == entry.id -> acc
        _ -> [entry | acc]
      end
    end)
    |> Enum.reverse()
  end
end
