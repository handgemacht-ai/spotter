defmodule Spotter.Config.Runtime do
  @moduledoc """
  Resolves effective configuration values with deterministic precedence.

  Each accessor returns `{value, source}` where source indicates
  where the value came from (`:db`, `:toml`, `:env`, or `:default`).
  """

  alias Spotter.Config.Setting
  alias Spotter.Services.LlmCredentials

  require Ash.Query

  @default_transcripts_dir "~/.claude/projects"
  @default_summary_model "claude-3-5-haiku-latest"
  @default_summary_budget 4000
  @default_prompt_patterns_max_prompts 500
  @default_prompt_patterns_max_chars 400
  @default_prompt_patterns_model "claude-haiku-4-5"

  @doc """
  Returns the effective transcripts directory.

  Precedence: DB override -> TOML `priv/spotter.toml` -> default `~/.claude/projects`.
  The `~` is expanded to the user's home directory.
  """
  @spec transcripts_dir() :: {String.t(), atom()}
  def transcripts_dir do
    case db_get("transcripts_dir") do
      {:ok, val} -> {expand_path(val), :db}
      :miss -> transcripts_dir_from_toml()
    end
  end

  @doc """
  Returns the effective summary model name.

  Precedence: DB override -> env `SPOTTER_SUMMARY_MODEL` -> default.
  """
  @spec summary_model() :: {String.t(), atom()}
  def summary_model do
    case db_get("summary_model") do
      {:ok, val} -> {val, :db}
      :miss -> summary_model_from_env()
    end
  end

  @doc """
  Returns the effective summary token budget.

  Precedence: DB override -> env `SPOTTER_SUMMARY_TOKEN_BUDGET` -> default.
  """
  @spec summary_token_budget() :: {pos_integer(), atom()}
  def summary_token_budget do
    case db_get("summary_token_budget") do
      {:ok, val} -> {parse_positive_integer(val, @default_summary_budget), :db}
      :miss -> summary_token_budget_from_env()
    end
  end

  @doc """
  Returns whether an Anthropic API key is configured.
  """
  @spec anthropic_key_present?() :: boolean()
  def anthropic_key_present? do
    match?({:ok, _}, LlmCredentials.anthropic_api_key())
  end

  @doc """
  Returns the max prompts per pattern analysis run.

  Precedence: DB override -> env `SPOTTER_PROMPT_PATTERNS_MAX_PROMPTS_PER_RUN` -> default 500.
  """
  @spec prompt_patterns_max_prompts_per_run() :: {pos_integer(), atom()}
  def prompt_patterns_max_prompts_per_run do
    case db_get("prompt_patterns_max_prompts_per_run") do
      {:ok, val} -> {parse_positive_integer(val, @default_prompt_patterns_max_prompts), :db}
      :miss -> prompt_patterns_max_prompts_from_env()
    end
  end

  @doc """
  Returns the max chars per prompt for pattern analysis.

  Precedence: DB override -> env `SPOTTER_PROMPT_PATTERNS_MAX_PROMPT_CHARS` -> default 400.
  """
  @spec prompt_patterns_max_prompt_chars() :: {pos_integer(), atom()}
  def prompt_patterns_max_prompt_chars do
    case db_get("prompt_patterns_max_prompt_chars") do
      {:ok, val} -> {parse_positive_integer(val, @default_prompt_patterns_max_chars), :db}
      :miss -> prompt_patterns_max_chars_from_env()
    end
  end

  @doc """
  Returns the model name for prompt pattern analysis.

  Precedence: DB override -> env `SPOTTER_PROMPT_PATTERNS_MODEL` -> default "claude-haiku-4-5".
  """
  @spec prompt_patterns_model() :: {String.t(), atom()}
  def prompt_patterns_model do
    case db_get("prompt_patterns_model") do
      {:ok, val} -> {val, :db}
      :miss -> prompt_patterns_model_from_env()
    end
  end

  # -- Private helpers --

  defp db_get(key) do
    case Setting
         |> Ash.Query.filter(key == ^key)
         |> Ash.read_one() do
      {:ok, %Setting{value: val}} -> {:ok, val}
      _ -> :miss
    end
  end

  defp transcripts_dir_from_toml do
    case read_toml_transcripts_dir() do
      {:ok, dir} -> {expand_path(dir), :toml}
      :error -> {expand_path(@default_transcripts_dir), :default}
    end
  end

  defp read_toml_transcripts_dir do
    path = Application.app_dir(:spotter, "priv/spotter.toml")

    with {:ok, content} <- File.read(path),
         {:ok, toml} <- Toml.decode(content),
         %{"transcripts_dir" => dir} when is_binary(dir) <- toml do
      {:ok, dir}
    else
      _ -> :error
    end
  end

  defp summary_model_from_env do
    case System.get_env("SPOTTER_SUMMARY_MODEL") do
      nil -> {@default_summary_model, :default}
      "" -> {@default_summary_model, :default}
      val -> {val, :env}
    end
  end

  defp summary_token_budget_from_env do
    case System.get_env("SPOTTER_SUMMARY_TOKEN_BUDGET") do
      nil -> {@default_summary_budget, :default}
      "" -> {@default_summary_budget, :default}
      val -> {parse_positive_integer(val, @default_summary_budget), :env}
    end
  end

  defp parse_positive_integer(val, fallback) when is_binary(val) do
    case Integer.parse(String.trim(val)) do
      {int, ""} when int > 0 -> int
      _ -> fallback
    end
  end

  defp prompt_patterns_max_prompts_from_env do
    case System.get_env("SPOTTER_PROMPT_PATTERNS_MAX_PROMPTS_PER_RUN") do
      nil -> {@default_prompt_patterns_max_prompts, :default}
      "" -> {@default_prompt_patterns_max_prompts, :default}
      val -> {parse_positive_integer(val, @default_prompt_patterns_max_prompts), :env}
    end
  end

  defp prompt_patterns_max_chars_from_env do
    case System.get_env("SPOTTER_PROMPT_PATTERNS_MAX_PROMPT_CHARS") do
      nil -> {@default_prompt_patterns_max_chars, :default}
      "" -> {@default_prompt_patterns_max_chars, :default}
      val -> {parse_positive_integer(val, @default_prompt_patterns_max_chars), :env}
    end
  end

  defp prompt_patterns_model_from_env do
    case System.get_env("SPOTTER_PROMPT_PATTERNS_MODEL") do
      nil ->
        {@default_prompt_patterns_model, :default}

      val when val in ["", " "] ->
        {@default_prompt_patterns_model, :default}

      val ->
        trimmed = String.trim(val)
        if trimmed == "", do: {@default_prompt_patterns_model, :default}, else: {trimmed, :env}
    end
  end

  defp expand_path(path) do
    String.replace(path, "~", System.user_home!())
  end
end
