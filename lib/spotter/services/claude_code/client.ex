defmodule Spotter.Services.ClaudeCode.Client do
  @moduledoc """
  Shared SDK client for querying Claude Code.

  Provides `query_text/3` and `query_json_schema/4` wrappers around
  `ClaudeAgentSDK.query/2` with API key gating, model normalization,
  tool lockdown, and OpenTelemetry tracing.
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Services.ClaudeCode.Model
  alias Spotter.Services.ClaudeCode.ResultExtractor
  alias Spotter.Services.LlmCredentials
  alias Spotter.Telemetry.TraceContext

  @default_timeout_ms 30_000

  @doc """
  Sends a text prompt to Claude and returns the text response.

  ## Options

    * `:model` - Raw model string (normalized via `Model.normalize/1`)
    * `:max_turns` - Max conversation turns (default 1)
    * `:timeout_ms` - Timeout in milliseconds (default 30_000)
  """
  @spec query_text(String.t(), String.t(), keyword()) ::
          {:ok, %{text: String.t(), model_used: String.t() | nil, messages: list()}}
          | {:error, term()}
  def query_text(system_prompt, user_prompt, opts \\ []) do
    with {:ok, _key} <- LlmCredentials.anthropic_api_key() do
      do_query(system_prompt, user_prompt, :text, nil, opts)
    end
  end

  @doc """
  Sends a prompt to Claude and returns structured JSON output.

  ## Options

  Same as `query_text/3`.
  """
  @spec query_json_schema(String.t(), String.t(), map(), keyword()) ::
          {:ok, %{output: map(), model_used: String.t() | nil, messages: list()}}
          | {:error, term()}
  def query_json_schema(system_prompt, user_prompt, schema, opts \\ []) do
    with {:ok, _key} <- LlmCredentials.anthropic_api_key() do
      do_query(system_prompt, user_prompt, :json_schema, schema, opts)
    end
  end

  # --- private ---

  defp do_query(system_prompt, user_prompt, format, schema, opts) do
    normalized_model = Model.normalize(opts[:model])
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    max_turns = Keyword.get(opts, :max_turns, 1)

    output_format = build_output_format(format, schema)
    format_label = if format == :text, do: "text", else: "json_schema"

    Tracer.with_span "spotter.claude_code.query" do
      Tracer.set_attribute("spotter.model_requested", normalized_model || "default")
      Tracer.set_attribute("spotter.output_format", format_label)
      Tracer.set_attribute("spotter.timeout_ms", timeout_ms)

      sdk_opts =
        build_options(system_prompt, normalized_model, output_format, timeout_ms, max_turns)

      try do
        messages =
          user_prompt
          |> ClaudeAgentSDK.query(sdk_opts)
          |> Enum.to_list()

        build_result(messages, format)
      rescue
        e ->
          reason = Exception.message(e)
          Tracer.set_status(:error, reason)
          {:error, reason}
      end
    end
  end

  defp build_options(system_prompt, model, output_format, timeout_ms, max_turns) do
    env =
      case TraceContext.current_traceparent() do
        tp when is_binary(tp) -> %{"TRACEPARENT" => tp}
        _ -> %{}
      end

    opts = %ClaudeAgentSDK.Options{
      system_prompt: system_prompt,
      tools: [],
      allowed_tools: [],
      permission_mode: :dont_ask,
      max_turns: max_turns,
      output_format: output_format,
      timeout_ms: timeout_ms,
      env: env
    }

    if model, do: %{opts | model: model}, else: opts
  end

  defp build_output_format(:text, _schema), do: :text
  defp build_output_format(:json_schema, schema), do: {:json_schema, schema}

  defp build_result(messages, :text) do
    case ResultExtractor.extract_text(messages) do
      {:ok, text} ->
        {:ok,
         %{
           text: text,
           model_used: ResultExtractor.extract_model_used(messages),
           messages: messages
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_result(messages, :json_schema) do
    case ResultExtractor.extract_structured_output(messages) do
      {:ok, output} ->
        {:ok,
         %{
           output: output,
           model_used: ResultExtractor.extract_model_used(messages),
           messages: messages
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
