defmodule Spotter.Services.WaitingSummary do
  @moduledoc """
  Generates concise waiting-state summaries from Claude session transcripts.

  Reads a transcript file, slices messages within a configurable character budget,
  and calls Claude via `claude_agent_sdk` to produce a short summary suitable for
  tmux overlay display. Falls back to a deterministic summary on any failure.
  """

  alias Spotter.Config.Runtime
  alias Spotter.Observability.ErrorReport
  alias Spotter.Services.ClaudeCode.Client
  alias Spotter.Services.WaitingSummary.SliceBuilder
  alias Spotter.Transcripts.JsonlParser

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

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
      summary = generate_summary(sliced, model, parsed.session_id, messages, window_meta)

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

  defp generate_summary(sliced_messages, model, session_id, all_messages, window_meta) do
    Tracer.with_span "spotter.waiting_summary.llm" do
      Tracer.set_attribute("spotter.model_requested", model)
      Tracer.set_attribute("spotter.input_chars", window_meta.input_chars)

      case call_llm(sliced_messages, model) do
        {:ok, text, model_used} ->
          Tracer.set_attribute("spotter.model_used", model_used || model)
          text

        {:error, reason} ->
          Logger.warning("WaitingSummary: LLM call failed: #{inspect(reason)}, using fallback")

          ErrorReport.set_trace_error("llm_error", inspect(reason), "services.waiting_summary")
          build_fallback_summary(session_id, all_messages)
      end
    end
  end

  defp call_llm([], _model), do: {:error, :no_messages}

  defp call_llm(messages, model) do
    input_text = Enum.map_join(messages, "\n", &SliceBuilder.message_text/1)

    {system_prompt, _source} = Runtime.waiting_summary_system_prompt()

    case Client.query_text(system_prompt, input_text, model: model, timeout_ms: 15_000) do
      {:ok, %{text: text, model_used: model_used}} -> {:ok, String.trim(text), model_used}
      {:error, reason} -> {:error, reason}
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
    {model, _source} = Runtime.summary_model()
    model
  end

  defp configured_budget do
    {budget, _source} = Runtime.summary_token_budget()
    budget
  end
end
