defmodule Spotter.Config do
  @moduledoc "Domain for app configuration overrides."
  use Ash.Domain

  resources do
    resource Spotter.Config.Setting
  end

  @doc """
  Returns the Anthropic API key or `nil`.

  Checks `SPOTTER_ANTHROPIC_API_KEY` first, falls back to `ANTHROPIC_API_KEY`.
  """
  @spec anthropic_api_key() :: String.t() | nil
  def anthropic_api_key do
    System.get_env("SPOTTER_ANTHROPIC_API_KEY") || System.get_env("ANTHROPIC_API_KEY")
  end

  @doc "Returns `true` when an Anthropic API key is available."
  @spec anthropic_api_key?() :: boolean()
  def anthropic_api_key? do
    not is_nil(anthropic_api_key())
  end
end
