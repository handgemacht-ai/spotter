defmodule Spotter.Services.PromptPatternScheduler do
  @moduledoc """
  Determines whether to auto-enqueue a prompt-pattern analysis run.

  Currently disabled — all public functions return a disabled/no-op result.
  The module is kept so callers don't need to be rewritten when the feature
  is re-enabled.
  """

  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Always returns `:disabled` while the prompt-pattern feature is off.
  """
  @spec schedule_auto_run_if_ready() :: :disabled
  def schedule_auto_run_if_ready do
    Tracer.with_span "spotter.prompt_pattern_scheduler.schedule_auto_run_if_ready" do
      Tracer.set_attribute("spotter.scheduler.result", "disabled")
      :disabled
    end
  end

  @doc """
  Returns 0 while the feature is disabled.
  """
  @spec sessions_remaining_for_auto_run() :: 0
  def sessions_remaining_for_auto_run, do: 0

  @doc """
  Returns a stable disabled payload for UI consumers.
  """
  @spec run_progress_for_ui() :: %{
          remaining: 0,
          cadence: 0,
          latest_status: :disabled
        }
  def run_progress_for_ui do
    %{remaining: 0, cadence: 0, latest_status: :disabled}
  end
end
