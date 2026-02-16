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
  @default_prompt_patterns_sessions_per_run 10
  @default_prompt_patterns_model "claude-haiku-4-5"
  @default_prompt_pattern_system_prompt """
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
  @default_session_distiller_system_prompt """
  You are summarizing a completed Claude Code session for a developer activity log.
  Given session metadata, linked commits, and a transcript slice, produce a structured summary.

  Your output must include:
  - "session_summary": 1-2 sentence overview of what was accomplished
  - "what_changed": concise bullet items of changes made
  - "key_files": objects with "path" and "reason" for files that matter
  - "commands_run": notable commands executed
  - "open_threads": unfinished work or follow-ups
  - "risks": potential issues or concerns

  Keep each field concise.
  Focus on session activity (tool calls, file snapshots, errors, transcript slice).
  Use commit information only as supporting context.
  """
  @default_project_rollup_system_prompt """
  You are summarizing a project's activity over a time period for a developer activity log.
  Given session summaries and commit information, produce a structured summary of the period.

  Your output must include:
  - "period_summary": 1-3 sentence overview of the period's activity
  - "themes": recurring themes or focus areas
  - "notable_commits": objects with "hash" and "why_it_matters"
  - "open_threads": unfinished work carried across sessions
  - "risks": potential issues or concerns

  Keep each field concise. Focus on committed work.
  """
  @default_waiting_summary_system_prompt """
  You are summarizing a Claude Code session for a tmux overlay notification.
  The developer has been away and Claude is waiting for input.
  Produce a concise summary (max 6 lines, ~60 chars per line) covering:
  - What was accomplished
  - What Claude is currently waiting for
  - Any errors or issues encountered
  Keep it actionable and scannable. No markdown formatting.
  """
  @default_commit_hotspot_explore_system_prompt """
  You are a code review triage analyst. Given diff statistics and hunk summaries for a commit,
  select which file regions are worth deep analysis for code quality hotspots.

  Focus on:
  - Complex logic changes (not just formatting or imports)
  - Error-prone patterns
  - Files with significant additions (not just deletions)

  Skip:
  - Binary files
  - Auto-generated files (migrations, lock files, compiled assets)
  - Test fixtures and sample data
  - Trivial changes (< 3 meaningful lines)

  Respond ONLY with valid JSON, no markdown fences:
  {"selected":[{"relative_path":"...","ranges":[{"line_start":1,"line_end":20}],"reason":"..."}],"skipped":[{"relative_path":"...","reason":"..."}]}
  """
  @default_commit_hotspot_main_system_prompt """
  You are a senior code reviewer analyzing a commit for quality hotspots.

  For each significant code region, identify hotspots worth reviewing. Score each on:
  - **complexity**: Logic complexity (0-100)
  - **duplication**: Copy-paste risk (0-100)
  - **error_handling**: Gaps in error handling (0-100)
  - **test_coverage**: Likelihood of being untested (0-100)
  - **change_risk**: Risk of introducing bugs (0-100)

  Provide an **overall_score** (0-100) representing review priority.

  Include:
  - The enclosing function/symbol name when identifiable
  - A short snippet (max 5 lines) showing the core of the hotspot
  - A concise reason explaining why this is a hotspot

  Respond ONLY with valid JSON, no markdown fences:
  {"hotspots":[{"relative_path":"...","symbol_name":"...","line_start":1,"line_end":20,"snippet":"...","reason":"...","overall_score":78.5,"rubric":{"complexity":80,"duplication":30,"error_handling":70,"test_coverage":60,"change_risk":85}}]}
  """
  @default_product_spec_system_prompt """
  You are a product specification analyst. Your job is to maintain a structured product specification based on code changes.

  %{prompt_body}
  """

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
  Returns the session cadence for automatic prompt-pattern runs.

  Precedence: DB override -> env `SPOTTER_PROMPT_PATTERNS_SESSIONS_PER_RUN` -> default 10.
  """
  @spec prompt_patterns_sessions_per_run() :: {pos_integer(), atom()}
  def prompt_patterns_sessions_per_run do
    case db_get("prompt_patterns_sessions_per_run") do
      {:ok, val} ->
        {parse_positive_integer(val, @default_prompt_patterns_sessions_per_run), :db}

      :miss ->
        prompt_patterns_sessions_per_run_from_env()
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

  @doc """
  Returns the system prompt for pattern analysis.

  Precedence: DB override -> env `SPOTTER_PROMPT_PATTERN_SYSTEM_PROMPT` -> default prompt.
  """
  @spec prompt_pattern_system_prompt() :: {String.t(), atom()}
  def prompt_pattern_system_prompt do
    resolve_setting_text(
      "prompt_pattern_system_prompt",
      "SPOTTER_PROMPT_PATTERN_SYSTEM_PROMPT",
      @default_prompt_pattern_system_prompt
    )
  end

  @doc """
  Returns the system prompt for session distillation.

  Precedence: DB override -> env `SPOTTER_SESSION_DISTILLER_SYSTEM_PROMPT` -> default prompt.
  """
  @spec session_distiller_system_prompt() :: {String.t(), atom()}
  def session_distiller_system_prompt do
    resolve_setting_text(
      "session_distiller_system_prompt",
      "SPOTTER_SESSION_DISTILLER_SYSTEM_PROMPT",
      @default_session_distiller_system_prompt
    )
  end

  @doc """
  Returns the system prompt for project rollup distillation.

  Precedence: DB override -> env `SPOTTER_PROJECT_ROLLUP_DISTILLER_SYSTEM_PROMPT` -> default prompt.
  """
  @spec project_rollup_system_prompt() :: {String.t(), atom()}
  def project_rollup_system_prompt do
    resolve_setting_text(
      "project_rollup_system_prompt",
      "SPOTTER_PROJECT_ROLLUP_DISTILLER_SYSTEM_PROMPT",
      @default_project_rollup_system_prompt
    )
  end

  @doc """
  Returns the system prompt for waiting summary generation.

  Precedence: DB override -> env `SPOTTER_WAITING_SUMMARY_SYSTEM_PROMPT` -> default prompt.
  """
  @spec waiting_summary_system_prompt() :: {String.t(), atom()}
  def waiting_summary_system_prompt do
    resolve_setting_text(
      "waiting_summary_system_prompt",
      "SPOTTER_WAITING_SUMMARY_SYSTEM_PROMPT",
      @default_waiting_summary_system_prompt
    )
  end

  @doc """
  Returns the commit hotspot explore system prompt.

  Precedence: DB override -> env `SPOTTER_COMMIT_HOTSPOT_EXPLORE_SYSTEM_PROMPT` -> default prompt.
  """
  @spec commit_hotspot_explore_system_prompt() :: {String.t(), atom()}
  def commit_hotspot_explore_system_prompt do
    resolve_setting_text(
      "commit_hotspot_explore_system_prompt",
      "SPOTTER_COMMIT_HOTSPOT_EXPLORE_SYSTEM_PROMPT",
      @default_commit_hotspot_explore_system_prompt
    )
  end

  @doc """
  Returns the commit hotspot main system prompt.

  Precedence: DB override -> env `SPOTTER_COMMIT_HOTSPOT_MAIN_SYSTEM_PROMPT` -> default prompt.
  """
  @spec commit_hotspot_main_system_prompt() :: {String.t(), atom()}
  def commit_hotspot_main_system_prompt do
    resolve_setting_text(
      "commit_hotspot_main_system_prompt",
      "SPOTTER_COMMIT_HOTSPOT_MAIN_SYSTEM_PROMPT",
      @default_commit_hotspot_main_system_prompt
    )
  end

  @doc """
  Returns the product specification system prompt template.

  Precedence: DB override -> env `SPOTTER_PRODUCT_SPEC_SYSTEM_PROMPT` -> default prompt.
  """
  @spec product_spec_system_prompt() :: {String.t(), atom()}
  def product_spec_system_prompt do
    resolve_setting_text(
      "product_spec_system_prompt",
      "SPOTTER_PRODUCT_SPEC_SYSTEM_PROMPT",
      @default_product_spec_system_prompt
    )
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

  defp prompt_patterns_sessions_per_run_from_env do
    case System.get_env("SPOTTER_PROMPT_PATTERNS_SESSIONS_PER_RUN") do
      nil -> {@default_prompt_patterns_sessions_per_run, :default}
      "" -> {@default_prompt_patterns_sessions_per_run, :default}
      val -> {parse_positive_integer(val, @default_prompt_patterns_sessions_per_run), :env}
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

  defp resolve_setting_text(key, env_var, default) when is_binary(default) do
    case db_get(key) do
      {:ok, val} -> {val, :db}
      :miss -> setting_text_from_env(env_var, default)
    end
  end

  defp setting_text_from_env(env_var, default) do
    case System.get_env(env_var) do
      nil ->
        {default, :default}

      "" ->
        {default, :default}

      value ->
        trimmed = String.trim(value)

        if trimmed == "" do
          {default, :default}
        else
          {trimmed, :env}
        end
    end
  end

  defp expand_path(path) do
    String.replace(path, "~", System.user_home!())
  end
end
