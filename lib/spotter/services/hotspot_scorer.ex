defmodule Spotter.Services.HotspotScorer do
  @moduledoc "Scores code snippets using Claude via LangChain for review prioritization."

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message

  @max_lines 500
  @rubric_factors ~w(complexity duplication error_handling test_coverage change_risk)

  @scoring_prompt """
  You are a code quality analyst. Score the following code snippet on these factors (0-100 each):

  - **complexity**: How complex is the logic? Higher = more complex, harder to understand.
  - **duplication**: How likely is this code duplicated or copy-pasted? Higher = more duplication risk.
  - **error_handling**: How poor is error handling? Higher = more gaps in error handling.
  - **test_coverage**: How likely is this code undertested? Higher = less likely to have tests.
  - **change_risk**: Given high churn, how risky are changes here? Higher = more risk of introducing bugs.

  Also provide an **overall_score** (0-100) representing review priority. Higher = needs more review attention.

  Respond ONLY with valid JSON, no markdown fences:
  {"overall_score": N, "complexity": N, "duplication": N, "error_handling": N, "test_coverage": N, "change_risk": N}
  """

  @doc """
  Score a code snippet for review priority.

  Returns `{:ok, %{overall_score: float, rubric: map}}` or `{:error, reason}`.
  """
  @spec score(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def score(relative_path, content, opts \\ []) do
    model = Keyword.get(opts, :model, "claude-haiku-4-5-20251001")
    lines = String.split(content, "\n")
    input_lines = length(lines)
    truncated = input_lines > @max_lines

    Tracer.with_span "spotter.hotspot_scorer.score" do
      Tracer.set_attribute("spotter.relative_path", relative_path)
      Tracer.set_attribute("spotter.model", model)
      Tracer.set_attribute("spotter.input_lines", input_lines)
      Tracer.set_attribute("spotter.input_truncated", truncated)

      with {:ok, llm} <- build_llm(model),
           {:ok, response} <- run_chain(llm, relative_path, content) do
        case parse_response(response) do
          {:ok, _} = result ->
            result

          {:error, reason} = error ->
            Tracer.set_status(:error, "parse_error: #{inspect(reason)}")
            error
        end
      else
        {:error, reason} = error ->
          Tracer.set_status(:error, "chain_error: #{inspect(reason)}")
          error
      end
    end
  end

  defp build_llm(model) do
    ChatAnthropic.new(%{
      model: model,
      stream: false,
      max_tokens: 256,
      temperature: 0.0
    })
  end

  defp run_chain(llm, relative_path, content) do
    user_message = """
    File: #{relative_path}

    ```
    #{truncate_content(content)}
    ```
    """

    chain_result =
      %{llm: llm}
      |> LLMChain.new!()
      |> LLMChain.add_message(Message.new_system!(@scoring_prompt))
      |> LLMChain.add_message(Message.new_user!(user_message))
      |> LLMChain.run()

    case chain_result do
      {:ok, %LLMChain{last_message: %Message{content: text}}} when is_binary(text) ->
        {:ok, text}

      {:ok, %LLMChain{last_message: %Message{content: parts}}} when is_list(parts) ->
        {:ok, parts}

      {:error, _chain, error} ->
        {:error, {:chain_error, error}}
    end
  end

  defp parse_response(text) when is_binary(text) do
    # Strip markdown fences if present despite instruction
    cleaned =
      text
      |> String.replace(~r/^```(?:json)?\s*/m, "")
      |> String.replace(~r/\s*```\s*$/m, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, json} ->
        validate_scores(json)

      {:error, reason} ->
        Logger.warning("HotspotScorer: failed to parse JSON: #{inspect(reason)}, raw: #{text}")
        {:error, {:json_parse_error, reason}}
    end
  end

  defp parse_response(content) when is_list(content) do
    case Enum.find_value(content, fn
           %{type: :text, content: text} -> text
           _ -> nil
         end) do
      nil -> {:error, :no_text_content}
      text -> parse_response(text)
    end
  end

  defp validate_scores(json) do
    overall = Map.get(json, "overall_score")

    rubric =
      Map.new(@rubric_factors, fn factor ->
        {factor, Map.get(json, factor)}
      end)

    cond do
      not is_number(overall) ->
        {:error, {:invalid_score, :overall_score, overall}}

      Enum.any?(rubric, fn {_k, v} -> not is_number(v) end) ->
        {:error, {:invalid_rubric, rubric}}

      true ->
        {:ok,
         %{
           overall_score: clamp(overall),
           rubric: Map.new(rubric, fn {k, v} -> {k, clamp(v)} end)
         }}
    end
  end

  defp clamp(n) when is_number(n), do: n |> max(0.0) |> min(100.0) |> Float.round(1)

  # Limit content to avoid token overflow - ~500 lines should be enough for scoring
  defp truncate_content(content) do
    lines = String.split(content, "\n")

    if length(lines) > @max_lines do
      lines
      |> Enum.take(@max_lines)
      |> Enum.join("\n")
      |> Kernel.<>("\n... (truncated)")
    else
      content
    end
  end
end
