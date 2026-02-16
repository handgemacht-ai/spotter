defmodule Spotter.Services.PromptPatternAgent do
  @moduledoc """
  Uses Claude via `claude_agent_sdk` to detect repeated prompt patterns
  from collected user prompts.

  Read-only agent with no tools — pure text analysis with structured output.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Services.ClaudeCode.Client

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
  """

  @json_schema %{
    "type" => "object",
    "required" => ["patterns"],
    "properties" => %{
      "patterns" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "required" => ["needle", "label", "examples"],
          "properties" => %{
            "needle" => %{"type" => "string"},
            "label" => %{"type" => "string"},
            "confidence" => %{"type" => ["number", "null"]},
            "examples" => %{"type" => "array", "items" => %{"type" => "string"}}
          }
        }
      }
    }
  }

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

      Tracer.set_attribute("spotter.model_requested", model)
      Tracer.set_attribute("spotter.prompts_count", length(prompts))

      user_input = build_user_input(prompts, patterns_max)

      case Client.query_json_schema(@system_prompt, user_input, @json_schema,
             model: model,
             timeout_ms: 30_000
           ) do
        {:ok, %{output: output, model_used: model_used, messages: _messages}} ->
          Tracer.set_attribute("spotter.model_used", model_used || model)

          case validate_output(output, patterns_max) do
            {:ok, patterns} ->
              {:ok, %{model_used: model_used || model, patterns: patterns}}

            {:error, _} = err ->
              err
          end

        {:error, _} = err ->
          err
      end
    end
  end

  @doc false
  def parse_response(raw, patterns_max \\ 10) do
    case parse_json(raw) do
      {:ok, map} -> validate_output(map, patterns_max)
      {:error, _} = err -> err
    end
  end

  @doc false
  def validate_output(%{"patterns" => patterns}, patterns_max) when is_list(patterns) do
    validated =
      patterns
      |> Enum.map(&validate_pattern/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.take(patterns_max)

    {:ok, validated}
  end

  def validate_output(_, _patterns_max), do: {:error, :invalid_response_shape}

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
