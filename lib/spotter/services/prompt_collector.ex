defmodule Spotter.Services.PromptCollector do
  @moduledoc "Collects user prompts from transcripts for pattern analysis."

  alias Spotter.Services.TranscriptRenderer
  alias Spotter.Transcripts.Message
  alias Spotter.Transcripts.Session

  require Ash.Query

  @page_size 500

  @type opts :: %{
          scope: :global | :project,
          project_id: String.t() | nil,
          timespan_days: pos_integer() | nil,
          prompt_limit: pos_integer(),
          max_prompt_chars: pos_integer(),
          now: DateTime.t() | nil
        }

  @doc """
  Collect user prompts matching the given scope, timespan, and limits.

  Returns `%{items: list(), meta: map()}`.
  """
  @spec collect(opts()) :: %{items: list(), meta: map()}
  def collect(opts) do
    now = Map.get(opts, :now) || DateTime.utc_now()
    cutoff = timespan_cutoff(opts[:timespan_days], now)
    session_ids = resolve_session_ids(opts[:scope], opts[:project_id])
    prompts_total = count_candidates(session_ids, cutoff)

    items = collect_items(session_ids, cutoff, opts[:prompt_limit], opts[:max_prompt_chars])

    %{
      items: items,
      meta: %{
        prompts_analyzed: length(items),
        unique_prompts: items |> Enum.map(& &1.prompt) |> Enum.uniq() |> length(),
        prompts_total: prompts_total
      }
    }
  end

  # -- Private --

  defp timespan_cutoff(nil, _now), do: nil

  defp timespan_cutoff(days, now) when is_integer(days) and days > 0 do
    DateTime.add(now, -days * 86_400, :second)
  end

  defp resolve_session_ids(scope, project_id) do
    query = Session |> Ash.Query.new()

    query =
      case scope do
        :project -> Ash.Query.filter(query, project_id == ^project_id)
        :global -> query
      end

    query
    |> Ash.Query.select([:id])
    |> Ash.read!()
    |> Enum.map(& &1.id)
  end

  defp count_candidates(session_ids, cutoff) do
    base_query(session_ids, cutoff)
    |> Ash.count!()
  end

  defp collect_items(session_ids, cutoff, limit, max_chars) do
    collect_pages(session_ids, cutoff, limit, max_chars, 0, [])
  end

  defp collect_pages(session_ids, cutoff, limit, max_chars, offset, acc) do
    messages =
      base_query(session_ids, cutoff)
      |> Ash.Query.sort(timestamp: :desc)
      |> Ash.Query.select([:id, :content, :session_id])
      |> Ash.Query.load(:session)
      |> Ash.Query.limit(@page_size)
      |> Ash.Query.offset(offset)
      |> Ash.read!()

    if messages == [] do
      acc
    else
      new_items =
        messages
        |> Enum.reject(&tool_result_wrapper?/1)
        |> Enum.map(fn msg -> extract_prompt(msg, max_chars) end)
        |> Enum.reject(&is_nil/1)

      acc = acc ++ new_items

      if length(acc) >= limit do
        Enum.take(acc, limit)
      else
        collect_pages(session_ids, cutoff, limit, max_chars, offset + @page_size, acc)
      end
    end
  end

  defp base_query(session_ids, cutoff) do
    query =
      Message
      |> Ash.Query.filter(type == :user and role == :user and is_nil(subagent_id))
      |> Ash.Query.filter(session_id in ^session_ids)

    case cutoff do
      nil -> query
      dt -> Ash.Query.filter(query, timestamp >= ^dt)
    end
  end

  defp tool_result_wrapper?(%Message{content: %{"blocks" => blocks}}) when is_list(blocks) do
    blocks != [] and Enum.all?(blocks, &(&1["type"] == "tool_result"))
  end

  defp tool_result_wrapper?(_), do: false

  defp extract_prompt(message, max_chars) do
    text =
      message.content
      |> TranscriptRenderer.extract_text()
      |> normalize_whitespace()

    if text == "" do
      nil
    else
      %{
        project_id: message.session.project_id,
        prompt: String.slice(text, 0, max_chars)
      }
    end
  end

  defp normalize_whitespace(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
