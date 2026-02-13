defmodule Spotter.Services.ProjectRollupDistiller.Anthropic do
  @moduledoc "Default LLM adapter for project rollup distillation using Claude via LangChain."
  @behaviour Spotter.Services.ProjectRollupDistiller

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias Spotter.Services.LlmCredentials

  require Logger

  @default_model "claude-3-5-haiku-latest"
  @default_timeout 15_000
  @max_tokens 500

  @system_prompt """
  You are summarizing a project's activity over a time period for a developer activity log.
  Given session summaries and commit information, produce a JSON summary of the period.

  Respond ONLY with valid JSON, no markdown fences:
  {
    "period_summary": "1-3 sentence overview of the period's activity",
    "themes": ["recurring themes or focus areas"],
    "notable_commits": [{"hash": "short_hash", "why_it_matters": "reason"}],
    "open_threads": ["unfinished work carried across sessions"],
    "risks": ["potential issues or concerns"]
  }

  Keep each field concise. Omit empty arrays. Focus on committed work.
  """

  @impl true
  def distill(pack, opts \\ []) do
    model = Keyword.get(opts, :model, configured_model())
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    case LlmCredentials.anthropic_api_key() do
      {:error, :missing_api_key} -> {:error, :missing_api_key}
      {:ok, api_key} -> call_llm(pack, model, api_key, timeout)
    end
  end

  defp call_llm(pack, model, api_key, timeout) do
    input_text = format_pack(pack)

    try do
      {:ok, llm} =
        ChatAnthropic.new(%{
          model: model,
          max_tokens: @max_tokens,
          temperature: 0.0,
          api_key: api_key
        })

      {:ok, chain} = LLMChain.new(%{llm: llm})

      chain
      |> LLMChain.add_message(Message.new_system!(@system_prompt))
      |> LLMChain.add_message(Message.new_user!(input_text))
      |> LLMChain.run(timeout: timeout)
      |> handle_response(model)
    rescue
      e -> {:error, {:exception, Exception.message(e)}}
    end
  end

  defp handle_response({:ok, updated_chain}, model) do
    case updated_chain.last_message do
      nil -> {:error, :empty_response}
      msg -> parse_response(msg.content |> to_string() |> String.trim(), model)
    end
  end

  defp handle_response({:error, _chain, reason}, _model), do: {:error, reason}

  defp parse_response(raw, model) do
    cleaned = strip_markdown_fences(raw)

    case Jason.decode(cleaned) do
      {:ok, json} when is_map_key(json, "period_summary") ->
        {:ok,
         %{
           summary_json: json,
           summary_text: format_summary_text(json),
           model_used: model,
           raw_response_text: raw
         }}

      {:ok, _} ->
        {:error, {:invalid_json, :missing_required_keys, raw}}

      {:error, reason} ->
        {:error, {:invalid_json, reason, raw}}
    end
  end

  defp format_summary_text(json) do
    sections = [
      json["period_summary"],
      format_list("Themes", json["themes"]),
      format_list("Open threads", json["open_threads"]),
      format_list("Risks", json["risks"])
    ]

    sections |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")
  end

  defp format_list(_heading, nil), do: nil
  defp format_list(_heading, []), do: nil

  defp format_list(heading, items) do
    bullets = Enum.map_join(items, "\n", &("- " <> to_string(&1)))
    "#{heading}:\n#{bullets}"
  end

  defp strip_markdown_fences(text) do
    text
    |> String.replace(~r/\A```(?:json)?\s*\n?/, "")
    |> String.replace(~r/\n?```\s*\z/, "")
    |> String.trim()
  end

  defp format_pack(pack) do
    sections = [
      "## Project: #{pack.project.name}",
      "Period: #{pack.bucket.bucket_kind} starting #{pack.bucket.bucket_start_date}",
      "## Sessions (#{length(pack.sessions)})",
      Jason.encode!(pack.sessions, pretty: true)
    ]

    Enum.join(sections, "\n\n")
  end

  defp configured_model do
    System.get_env("SPOTTER_PROJECT_ROLLUP_MODEL") || @default_model
  end
end
