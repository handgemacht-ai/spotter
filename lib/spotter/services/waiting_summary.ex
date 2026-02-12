defmodule Spotter.Services.WaitingSummary do
  @moduledoc """
  Generates concise waiting-state summaries from Claude session transcripts.

  Reads a transcript file, slices messages within a configurable character budget,
  and calls a Haiku model to produce a short summary suitable for tmux overlay display.
  Falls back to a deterministic summary on any LLM/parse failure.
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias Spotter.Services.WaitingSummary.SliceBuilder
  alias Spotter.Transcripts.JsonlParser

  require Logger

  @default_model "claude-3-5-haiku-latest"
  @default_budget 4000
  @llm_timeout 15_000

  @type summary_result :: %{
          summary: String.t(),
          input_chars: non_neg_integer(),
          source_window: %{head_messages: non_neg_integer(), tail_messages: non_neg_integer()}
        }

  @doc """
  Generates a summary from a transcript file.

  Returns `{:ok, result}` with summary text and metrics,
  or `{:error, reason}` for structural failures (missing file path).

  Options:
    - `:token_budget` - character budget for input slicing (default from env)
    - `:model` - LLM model name (default from env)
  """
  @spec generate(String.t(), keyword()) :: {:ok, summary_result()} | {:error, term()}
  def generate(transcript_path, opts \\ []) do
    budget = Keyword.get(opts, :token_budget, configured_budget())
    model = Keyword.get(opts, :model, configured_model())

    with {:ok, parsed} <- parse_transcript(transcript_path),
         messages = parsed.messages,
         {sliced, window_meta} <- SliceBuilder.build(messages, budget: budget) do
      summary = generate_summary(sliced, model, parsed.session_id, messages)

      {:ok,
       %{
         summary: summary,
         input_chars: window_meta.input_chars,
         source_window: %{
           head_messages: window_meta.head_messages,
           tail_messages: window_meta.tail_messages
         }
       }}
    end
  end

  defp parse_transcript(path) do
    case JsonlParser.parse_session_file(path) do
      {:ok, _} = result ->
        result

      {:error, reason} ->
        Logger.warning("WaitingSummary: transcript parse failed: #{inspect(reason)}")
        {:error, :transcript_parse_failed}
    end
  end

  defp generate_summary(sliced_messages, model, session_id, all_messages) do
    case call_llm(sliced_messages, model) do
      {:ok, text} ->
        text

      {:error, reason} ->
        Logger.warning("WaitingSummary: LLM call failed: #{inspect(reason)}, using fallback")
        build_fallback_summary(session_id, all_messages)
    end
  end

  defp call_llm([], _model), do: {:error, :no_messages}

  defp call_llm(messages, model) do
    input_text =
      Enum.map_join(messages, "\n", &SliceBuilder.message_text/1)

    system_prompt = """
    You are summarizing a Claude Code session for a tmux overlay notification.
    The developer has been away and Claude is waiting for input.
    Produce a concise summary (max 6 lines, ~60 chars per line) covering:
    - What was accomplished
    - What Claude is currently waiting for
    - Any errors or issues encountered
    Keep it actionable and scannable. No markdown formatting.
    """

    try do
      {:ok, llm} =
        ChatAnthropic.new(%{
          model: model,
          max_tokens: 200,
          temperature: 0.0,
          api_key: anthropic_api_key()
        })

      {:ok, chain} =
        LLMChain.new(%{llm: llm})

      chain
      |> LLMChain.add_message(Message.new_system!(system_prompt))
      |> LLMChain.add_message(Message.new_user!(input_text))
      |> LLMChain.run(timeout: @llm_timeout)
      |> case do
        {:ok, _chain, response} when is_struct(response) ->
          {:ok, response.content |> to_string() |> String.trim()}

        {:ok, _chain, nil} ->
          {:error, :empty_response}

        {:error, _chain, reason} ->
          {:error, reason}

        other ->
          {:error, {:unexpected_response, other}}
      end
    rescue
      e ->
        {:error, {:exception, Exception.message(e)}}
    end
  end

  @doc """
  Builds a deterministic fallback summary without LLM.
  """
  @spec build_fallback_summary(String.t() | nil, [map()]) :: String.t()
  def build_fallback_summary(session_id, messages) do
    short_id = if session_id, do: String.slice(session_id, 0, 8), else: "unknown"
    total = length(messages)

    tool_count =
      Enum.count(messages, fn m -> m[:type] in [:tool_use, :tool_result] end)

    last_action = find_last_user_action(messages)

    lines =
      [
        "Session: #{short_id}...",
        "Messages: #{total}, Tool calls: #{div(tool_count, 2)}",
        last_action && "Last action: #{last_action}",
        "Claude is waiting for your input."
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(lines, "\n")
  end

  defp find_last_user_action(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn msg ->
      if msg[:type] == :tool_use do
        extract_tool_name(msg)
      end
    end)
  end

  defp extract_tool_name(msg) do
    case msg[:content] do
      %{"blocks" => blocks} when is_list(blocks) ->
        blocks
        |> Enum.find_value(fn
          %{"type" => "tool_use", "name" => name} -> name
          _ -> nil
        end)

      _ ->
        nil
    end
  end

  defp configured_model do
    System.get_env("SPOTTER_SUMMARY_MODEL") || @default_model
  end

  defp configured_budget do
    case System.get_env("SPOTTER_SUMMARY_TOKEN_BUDGET") do
      nil -> @default_budget
      val -> String.to_integer(val)
    end
  end

  defp anthropic_api_key do
    System.get_env("ANTHROPIC_API_KEY") || ""
  end
end
