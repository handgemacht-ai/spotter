defmodule Spotter.Services.LlmCredentials do
  @moduledoc """
  Shared credential resolution for LLM services.

  Used by `claude_agent_sdk` for non-interactive background runs
  (summaries, distillation, hotspot analysis).
  """

  @doc """
  Resolves the Anthropic API key from the environment.

  Returns `{:ok, key}` when a non-blank key is found,
  or `{:error, :missing_api_key}` otherwise.
  """
  @spec anthropic_api_key() :: {:ok, String.t()} | {:error, :missing_api_key}
  def anthropic_api_key do
    case System.get_env("SPOTTER_ANTHROPIC_API_KEY") do
      nil -> {:error, :missing_api_key}
      key -> if String.trim(key) == "", do: {:error, :missing_api_key}, else: {:ok, key}
    end
  end
end
