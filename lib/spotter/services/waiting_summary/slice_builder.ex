defmodule Spotter.Services.WaitingSummary.SliceBuilder do
  @moduledoc """
  Builds a budget-constrained input slice from transcript messages.

  Takes messages from both the head and tail of a conversation,
  alternating until the character budget is reached. Avoids
  duplicate overlap when the transcript is short.
  """

  @default_budget 4000

  @doc """
  Builds a sliced window of messages from head and tail within budget.

  Returns `{selected_messages, metadata}` where metadata includes
  `:head_messages`, `:tail_messages`, and `:input_chars`.

  Options:
    - `:budget` - character budget (default #{@default_budget})
  """
  @spec build([map()], keyword()) :: {[map()], map()}
  def build(messages, opts \\ []) do
    budget = Keyword.get(opts, :budget, @default_budget)

    if Enum.empty?(messages) do
      {[], %{head_messages: 0, tail_messages: 0, input_chars: 0}}
    else
      do_build(messages, budget)
    end
  end

  defp do_build(messages, budget) do
    total = length(messages)
    head_indices = 0..(total - 1) |> Enum.to_list()
    tail_indices = (total - 1)..0//-1 |> Enum.to_list()

    {selected_indices, _remaining} =
      interleave_indices(head_indices, tail_indices, messages, budget)

    sorted_indices = selected_indices |> MapSet.to_list() |> Enum.sort()

    selected = Enum.map(sorted_indices, &Enum.at(messages, &1))

    head_count =
      sorted_indices
      |> Enum.count(fn i -> i < div(total, 2) end)

    tail_count = length(sorted_indices) - head_count

    input_chars =
      selected
      |> Enum.map(&message_char_size/1)
      |> Enum.sum()

    {selected,
     %{
       head_messages: head_count,
       tail_messages: tail_count,
       input_chars: input_chars
     }}
  end

  defp interleave_indices(head, tail, messages, budget) do
    interleave_indices(head, tail, messages, budget, MapSet.new(), 0, :head)
  end

  defp interleave_indices([], [], _messages, _budget, selected, used, _turn) do
    {selected, budget_remaining(used, used)}
  end

  defp interleave_indices(head, tail, messages, budget, selected, used, _turn)
       when used >= budget do
    _ = {head, tail, messages}
    {selected, budget - used}
  end

  defp interleave_indices(head, tail, messages, budget, selected, used, :head) do
    case pick_next(head, selected) do
      {nil, _rest} ->
        interleave_indices([], tail, messages, budget, selected, used, :tail)

      {idx, rest} ->
        msg = Enum.at(messages, idx)
        size = message_char_size(msg)

        if used + size <= budget do
          interleave_indices(
            rest,
            tail,
            messages,
            budget,
            MapSet.put(selected, idx),
            used + size,
            :tail
          )
        else
          {selected, budget - used}
        end
    end
  end

  defp interleave_indices(head, tail, messages, budget, selected, used, :tail) do
    case pick_next(tail, selected) do
      {nil, _rest} ->
        interleave_indices(head, [], messages, budget, selected, used, :head)

      {idx, rest} ->
        msg = Enum.at(messages, idx)
        size = message_char_size(msg)

        if used + size <= budget do
          interleave_indices(
            head,
            rest,
            messages,
            budget,
            MapSet.put(selected, idx),
            used + size,
            :head
          )
        else
          {selected, budget - used}
        end
    end
  end

  defp pick_next([], _selected), do: {nil, []}

  defp pick_next([idx | rest], selected) do
    if MapSet.member?(selected, idx) do
      pick_next(rest, selected)
    else
      {idx, rest}
    end
  end

  defp budget_remaining(used, _budget), do: -used

  @doc """
  Extracts a compact text representation from a message for summarization.
  """
  @spec message_text(map()) :: String.t()
  def message_text(msg) do
    role = msg[:role] || msg[:type] || :unknown
    content = extract_text_content(msg[:content])
    "[#{role}] #{content}"
  end

  @doc """
  Returns the character size of a message for budget accounting.
  """
  @spec message_char_size(map()) :: non_neg_integer()
  def message_char_size(msg) do
    msg |> message_text() |> String.length()
  end

  defp extract_text_content(nil), do: ""
  defp extract_text_content(%{"text" => text}) when is_binary(text), do: text

  defp extract_text_content(%{"blocks" => blocks}) when is_list(blocks) do
    blocks
    |> Enum.map(&extract_block_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp extract_text_content(content) when is_binary(content), do: content
  defp extract_text_content(_), do: ""

  defp extract_block_text(%{"type" => "text", "text" => text}), do: text

  defp extract_block_text(%{"type" => "tool_use", "name" => name}),
    do: "[tool: #{name}]"

  defp extract_block_text(%{"type" => "tool_result"}),
    do: "[tool result]"

  defp extract_block_text(_), do: ""
end
