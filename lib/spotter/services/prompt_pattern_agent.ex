defmodule Spotter.Services.PromptPatternAgent do
  @moduledoc """
  Uses Claude via LangChain to detect repeated prompt patterns from collected user prompts.

  Read-only agent with no tools — pure text analysis.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias Spotter.Services.LlmCredentials

  @system_prompt """
  You are a prompt pattern analyst. Given a list of user prompts from Claude Code sessions,
  identify repeated *substring* patterns ("needles") that appear across multiple prompts.

  Focus on:
  - Common command patterns (e.g. "fix the bug", "add tests for", "refactor")
  - Repeated workflow phrases (e.g. "commit these changes", "run the tests")
  - Domain-specific repeated instructions

  Rules:
  - Each needle must be plain text (no regex), between 6 and 80 characters
  - Each label must be non-empty, at most 60 characters
  - Confidence is a number between 0 and 1
  - Include up to 5 example prompts that contain the needle
  - Return at most the requested number of patterns

  Respond ONLY with valid JSON, no markdown fences:
  {"patterns":[{"needle":"...","label":"...","confidence":0.85,"examples":["..."]}]}
  """

  @doc """
  Analyze prompts for repeated patterns.

  Returns `{:ok, %{model_used: String.t(), patterns: list()}}` or `{:error, term()}`.
  """
  @spec analyze([String.t()], keyword()) ::
          {:ok, %{model_used: String.t(), patterns: list()}} | {:error, term()}
  def analyze(prompts, opts \\ []) do
    Tracer.with_span "spotter.prompt_pattern_agent.analyze" do
      model = Keyword.get(opts, :model, "claude-haiku-4-5")
      patterns_max = Keyword.get(opts, :patterns_max, 10)

      Tracer.set_attribute("spotter.model", model)
      Tracer.set_attribute("spotter.prompts_count", length(prompts))

      with {:ok, api_key} <- LlmCredentials.anthropic_api_key(),
           {:ok, raw} <- call_llm(model, api_key, build_user_input(prompts, patterns_max)),
           {:ok, patterns} <- parse_response(raw, patterns_max) do
        {:ok, %{model_used: model, patterns: patterns}}
      end
    end
  end

  @doc false
  def parse_response(raw, patterns_max \\ 10) do
    case parse_json(raw) do
      {:ok, %{"patterns" => patterns}} when is_list(patterns) ->
        validated =
          patterns
          |> Enum.map(&validate_pattern/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.take(patterns_max)

        {:ok, validated}

      {:ok, _} ->
        {:error, :invalid_response_shape}

      {:error, _} = err ->
        err
    end
  end

  defp build_user_input(prompts, patterns_max) do
    numbered =
      prompts
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {prompt, i} -> "#{i}. #{prompt}" end)

    """
    Analyze these #{length(prompts)} user prompts and find up to #{patterns_max} repeated substring patterns:

    #{numbered}
    """
  end

  defp call_llm(model, api_key, user_input) do
    with {:ok, llm} <- build_llm(model, api_key),
         {:ok, result_chain} <- run_chain(llm, user_input) do
      extract_text(result_chain)
    else
      {:error, _chain, error} -> {:error, {:chain_error, error}}
      {:error, _} = err -> err
    end
  end

  defp build_llm(model, api_key) do
    ChatAnthropic.new(%{
      model: model,
      stream: false,
      max_tokens: 2048,
      temperature: 0.0,
      api_key: api_key
    })
  end

  defp run_chain(llm, user_input) do
    %{llm: llm}
    |> LLMChain.new!()
    |> LLMChain.add_message(Message.new_system!(@system_prompt))
    |> LLMChain.add_message(Message.new_user!(user_input))
    |> LLMChain.run()
  end

  defp extract_text(%LLMChain{last_message: %Message{content: text}}) when is_binary(text) do
    {:ok, text}
  end

  defp extract_text(%LLMChain{last_message: %Message{content: parts}}) when is_list(parts) do
    case Enum.find_value(parts, &extract_text_part/1) do
      nil -> {:error, :no_text_content}
      text -> {:ok, text}
    end
  end

  defp extract_text(_), do: {:error, :unexpected_response}

  defp extract_text_part(%{type: :text, content: text}), do: text
  defp extract_text_part(_), do: nil

  defp validate_pattern(%{
         "needle" => needle,
         "label" => label,
         "confidence" => confidence,
         "examples" => examples
       })
       when is_binary(needle) and is_binary(label) and is_list(examples) do
    needle_len = String.length(needle)
    label_len = String.length(label)

    cond do
      needle_len < 6 or needle_len > 80 -> nil
      label_len == 0 or label_len > 60 -> nil
      true -> build_pattern(needle, label, confidence, examples)
    end
  end

  defp validate_pattern(_), do: nil

  defp build_pattern(needle, label, confidence, examples) do
    %{
      "needle" => needle,
      "label" => label,
      "confidence" => normalize_confidence(confidence),
      "examples" => Enum.take(examples, 5) |> Enum.filter(&is_binary/1)
    }
  end

  defp normalize_confidence(n) when is_number(n),
    do: (n * 1.0) |> max(0.0) |> min(1.0) |> Float.round(2)

  defp normalize_confidence(_), do: nil

  defp parse_json(text) do
    cleaned =
      text
      |> String.replace(~r/^```(?:json)?\s*/m, "")
      |> String.replace(~r/\s*```\s*$/m, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:json_parse_error, reason}}
    end
  end
end
