defmodule Spotter.Services.SessionDistiller.Anthropic do
  @moduledoc "Default LLM adapter for session distillation using Claude via LangChain."
  @behaviour Spotter.Services.SessionDistiller

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Message
  alias Spotter.Services.LlmCredentials

  require Logger

  @default_model "claude-3-5-haiku-latest"
  @default_timeout 15_000
  @max_tokens 400

  @system_prompt """
  You are summarizing a completed Claude Code session for a developer activity log.
  Given session metadata, linked commits, and a transcript slice, produce a JSON summary.

  Respond ONLY with valid JSON, no markdown fences:
  {
    "session_summary": "1-2 sentence overview of what was accomplished",
    "what_changed": ["concise bullet items of changes made"],
    "key_files": [{"path": "relative/path", "reason": "why this file matters"}],
    "commands_run": ["notable commands executed"],
    "open_threads": ["unfinished work or follow-ups"],
    "risks": ["potential issues or concerns"]
  }

  Keep each field concise. Omit empty arrays. Focus on committed work.
  """

  @impl true
  def distill(pack, opts \\ []) do
    model = Keyword.get(opts, :model, configured_model())
    timeout = Keyword.get(opts, :timeout, configured_timeout())

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
      e ->
        {:error, {:exception, Exception.message(e)}}
    end
  end

  defp handle_response({:ok, updated_chain}, model) do
    case updated_chain.last_message do
      nil ->
        {:error, :empty_response}

      msg ->
        raw = msg.content |> to_string() |> String.trim()
        parse_response(raw, model)
    end
  end

  defp handle_response({:error, _chain, reason}, _model), do: {:error, reason}

  defp parse_response(raw, model) do
    cleaned = strip_markdown_fences(raw)

    case Jason.decode(cleaned) do
      {:ok, json} ->
        validate_and_build(json, raw, model)

      {:error, reason} ->
        {:error, {:invalid_json, reason, raw}}
    end
  end

  defp validate_and_build(json, raw, model) do
    required = ["session_summary"]

    if Enum.all?(required, &Map.has_key?(json, &1)) do
      {:ok,
       %{
         summary_json: json,
         summary_text: format_summary_text(json),
         model_used: model,
         raw_response_text: raw
       }}
    else
      {:error, {:invalid_json, :missing_required_keys, raw}}
    end
  end

  defp format_summary_text(json) do
    sections = [
      json["session_summary"],
      format_list("What changed", json["what_changed"]),
      format_key_files(json["key_files"]),
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

  defp format_key_files(nil), do: nil
  defp format_key_files([]), do: nil

  defp format_key_files(files) do
    bullets =
      Enum.map_join(files, "\n", fn
        %{"path" => p, "reason" => r} -> "- #{p} - #{r}"
        %{"path" => p} -> "- #{p}"
        other -> "- #{inspect(other)}"
      end)

    "Key files:\n#{bullets}"
  end

  defp strip_markdown_fences(text) do
    text
    |> String.replace(~r/\A```(?:json)?\s*\n?/, "")
    |> String.replace(~r/\n?```\s*\z/, "")
    |> String.trim()
  end

  defp format_pack(pack) do
    sections = [
      "## Session",
      Jason.encode!(pack.session, pretty: true),
      "## Commits (#{length(pack.commits)})",
      Jason.encode!(pack.commits, pretty: true),
      "## Stats",
      Jason.encode!(pack.stats, pretty: true),
      "## Transcript Slice",
      pack.transcript_slice
    ]

    Enum.join(sections, "\n\n")
  end

  defp configured_model do
    System.get_env("SPOTTER_SESSION_DISTILL_MODEL") || @default_model
  end

  defp configured_timeout do
    case System.get_env("SPOTTER_DISTILL_TIMEOUT_MS") do
      nil -> @default_timeout
      "" -> @default_timeout
      val -> parse_int(val, @default_timeout)
    end
  end

  defp parse_int(val, fallback) do
    case Integer.parse(String.trim(val)) do
      {int, ""} when int > 0 -> int
      _ -> fallback
    end
  end
end
