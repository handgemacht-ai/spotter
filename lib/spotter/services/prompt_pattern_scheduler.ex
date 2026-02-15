defmodule Spotter.Services.PromptPatternScheduler do
  @moduledoc """
  Determines whether to auto-enqueue a prompt-pattern analysis run
  based on the number of ended sessions since the last completed run.
  """

  alias Spotter.Config.Runtime
  alias Spotter.Transcripts.Jobs.ComputePromptPatterns
  alias Spotter.Transcripts.{PromptPatternRun, Session}

  require Ash.Query
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Checks whether enough sessions have ended since the last global run
  and enqueues a ComputePromptPatterns job if the threshold is met.

  Returns `:enqueued`, `:not_ready`, or `:already_running`.
  """
  @spec schedule_auto_run_if_ready() :: :enqueued | :not_ready | :already_running
  def schedule_auto_run_if_ready do
    Tracer.with_span "spotter.prompt_pattern_scheduler.schedule_auto_run_if_ready" do
      case latest_global_run() do
        %PromptPatternRun{status: status} when status in [:queued, :running] ->
          Tracer.set_attribute("spotter.scheduler.result", "already_running")
          :already_running

        latest_run ->
          {cadence, _source} = Runtime.prompt_patterns_sessions_per_run()
          ended_count = ended_sessions_since(latest_run)

          Tracer.set_attribute("spotter.scheduler.cadence", cadence)
          Tracer.set_attribute("spotter.scheduler.ended_count", ended_count)

          if ended_count >= cadence do
            enqueue_global_run()
            Tracer.set_attribute("spotter.scheduler.result", "enqueued")
            :enqueued
          else
            Tracer.set_attribute("spotter.scheduler.result", "not_ready")
            :not_ready
          end
      end
    end
  end

  @doc """
  Returns the number of sessions remaining before the next automatic run.
  """
  @spec sessions_remaining_for_auto_run() :: non_neg_integer()
  def sessions_remaining_for_auto_run do
    latest_run = latest_global_run()
    {cadence, _source} = Runtime.prompt_patterns_sessions_per_run()
    ended_count = ended_sessions_since(latest_run)
    max(cadence - ended_count, 0)
  end

  @doc """
  Returns a map with progress info suitable for UI display.
  """
  @spec run_progress_for_ui() :: %{
          remaining: non_neg_integer(),
          cadence: pos_integer(),
          latest_status: atom() | nil
        }
  def run_progress_for_ui do
    latest_run = latest_global_run()
    {cadence, _source} = Runtime.prompt_patterns_sessions_per_run()
    ended_count = ended_sessions_since(latest_run)

    %{
      remaining: max(cadence - ended_count, 0),
      cadence: cadence,
      latest_status: if(latest_run, do: latest_run.status, else: nil)
    }
  end

  # --- Private ---

  defp latest_global_run do
    PromptPatternRun
    |> Ash.Query.filter(scope == :global and is_nil(project_id))
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> List.first()
  end

  defp ended_sessions_since(nil) do
    Session
    |> Ash.Query.filter(not is_nil(hook_ended_at))
    |> Ash.count!()
  end

  defp ended_sessions_since(%PromptPatternRun{inserted_at: inserted_at}) do
    Session
    |> Ash.Query.filter(not is_nil(hook_ended_at) and hook_ended_at > ^inserted_at)
    |> Ash.count!()
  end

  defp enqueue_global_run do
    %{scope: "global", project_id: nil, timespan_days: 30}
    |> ComputePromptPatterns.new()
    |> Oban.insert()
  end
end
