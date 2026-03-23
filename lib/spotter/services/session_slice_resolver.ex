defmodule Spotter.Services.SessionSliceResolver do
  @moduledoc """
  Resolves a SessionSlice against a session's messages, producing windowed
  subsets of messages around highlighted tool_use_ids.
  """

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Transcripts.Message

  @doc """
  Resolves a slice against a session, returning windowed message groups.

  Returns `{:ok, windows}` where windows is a list of message lists (one per
  merged window), or `{:error, :cross_session_slice}` if the slice belongs
  to a different session.
  """
  def resolve(session, slice) do
    Tracer.with_span "spotter.session_slice.resolve" do
      Tracer.set_attribute("session_id", session.id)
      Tracer.set_attribute("slice_id", slice.id)

      if slice.session_id != session.id do
        Tracer.set_status(:error, "cross_session_slice")
        {:error, :cross_session_slice}
      else
        messages = load_messages(session)
        do_resolve(messages, slice)
      end
    end
  end

  defp load_messages(session) do
    Message
    |> Ash.Query.filter(session_id == ^session.id and is_nil(subagent_id))
    |> Ash.Query.sort(ordinal: :asc_nils_last, timestamp: :asc)
    |> Ash.read!()
  end

  defp do_resolve(messages, slice) do
    tool_use_ids = MapSet.new(slice.highlight_tool_use_ids || [])

    highlighted_indices =
      messages
      |> Enum.with_index()
      |> Enum.flat_map(fn {msg, idx} ->
        if message_has_tool_use_id?(msg, tool_use_ids), do: [idx], else: []
      end)

    if highlighted_indices == [] do
      {:ok, []}
    else
      context_before = slice.context_before_lines || 0
      context_after = slice.context_after_lines || 0
      max_idx = length(messages) - 1

      raw_windows =
        highlighted_indices
        |> Enum.map(fn idx ->
          {max(0, idx - context_before), min(max_idx, idx + context_after)}
        end)

      merged = merge_windows(raw_windows)

      windows =
        Enum.map(merged, fn {start_idx, end_idx} ->
          Enum.slice(messages, start_idx..end_idx)
        end)

      {:ok, windows}
    end
  end

  defp message_has_tool_use_id?(msg, tool_use_ids) do
    cond do
      msg.tool_use_id && MapSet.member?(tool_use_ids, msg.tool_use_id) ->
        true

      match?(%{"blocks" => [_ | _]}, msg.content) ->
        msg.content["blocks"]
        |> Enum.any?(fn block ->
          (block["type"] == "tool_use" && MapSet.member?(tool_use_ids, block["id"])) ||
            (block["type"] == "tool_result" &&
               MapSet.member?(tool_use_ids, block["tool_use_id"]))
        end)

      true ->
        false
    end
  end

  defp merge_windows([]), do: []

  defp merge_windows(windows) do
    windows
    |> Enum.sort()
    |> Enum.reduce([], fn
      {s, e}, [] ->
        [{s, e}]

      {s, e}, [{prev_s, prev_e} | rest] when s <= prev_e + 1 ->
        [{prev_s, max(prev_e, e)} | rest]

      window, acc ->
        [window | acc]
    end)
    |> Enum.reverse()
  end
end
