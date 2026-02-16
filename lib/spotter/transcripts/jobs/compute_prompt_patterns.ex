defmodule Spotter.Transcripts.Jobs.ComputePromptPatterns do
  @moduledoc "Oban worker that collects user prompts, detects patterns via LLM, and persists results."

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [keys: [:scope, :project_id, :timespan_days], period: 10]

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Config.Runtime
  alias Spotter.Services.{LlmCredentials, PromptCollector}
  alias Spotter.Transcripts.{PromptPattern, PromptPatternRun}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    Tracer.with_span "spotter.compute_prompt_patterns.perform" do
      scope = parse_scope(args["scope"])
      project_id = args["project_id"]
      timespan_days = args["timespan_days"]

      Tracer.set_attribute("spotter.scope", to_string(scope))
      Tracer.set_attribute("spotter.project_id", project_id || "")
      Tracer.set_attribute("spotter.timespan_days", timespan_days || 0)

      {prompt_limit, _} = Runtime.prompt_patterns_max_prompts_per_run()
      {max_prompt_chars, _} = Runtime.prompt_patterns_max_prompt_chars()
      {model, _} = Runtime.prompt_patterns_model()

      Tracer.set_attribute("spotter.prompt_limit", prompt_limit)

      run = create_run!(scope, project_id, timespan_days, prompt_limit, max_prompt_chars)

      try do
        do_perform(run, scope, project_id, timespan_days, prompt_limit, max_prompt_chars, model)
      rescue
        e ->
          error_msg = Exception.message(e) |> String.slice(0, 500)
          Tracer.set_status(:error, error_msg)
          fail_run(run, error_msg)
          :ok
      end
    end
  end

  defp do_perform(run, scope, project_id, timespan_days, prompt_limit, max_prompt_chars, model) do
    run = mark_running!(run)

    case LlmCredentials.anthropic_api_key() do
      {:error, :missing_api_key} ->
        fail_run(run, "missing_api_key")
        :ok

      {:ok, _api_key} ->
        run_analysis(run, scope, project_id, timespan_days, prompt_limit, max_prompt_chars, model)
    end
  end

  defp run_analysis(run, scope, project_id, timespan_days, prompt_limit, max_prompt_chars, model) do
    collection =
      PromptCollector.collect(%{
        scope: scope,
        project_id: project_id,
        timespan_days: timespan_days,
        prompt_limit: prompt_limit,
        max_prompt_chars: max_prompt_chars
      })

    prompts = Enum.map(collection.items, & &1.prompt)

    Tracer.set_attribute("spotter.prompts_analyzed", length(prompts))

    agent_module = agent_module()

    case agent_module.analyze(prompts, model: model) do
      {:ok, %{model_used: model_used, patterns: patterns}} ->
        persist_patterns(run, patterns, collection.items)
        complete_run!(run, collection.meta, model_used)
        :ok

      {:error, reason} ->
        error_msg = inspect(reason) |> String.slice(0, 500)
        Tracer.set_status(:error, error_msg)
        fail_run(run, error_msg)
        :ok
    end
  end

  defp persist_patterns(run, patterns, collected_items) do
    Enum.each(patterns, fn pattern ->
      needle = pattern["needle"]
      needle_lower = String.downcase(needle)

      matching_items =
        Enum.filter(collected_items, fn item ->
          String.contains?(String.downcase(item.prompt), needle_lower)
        end)

      count_total = length(matching_items)

      project_counts =
        matching_items
        |> Enum.group_by(& &1.project_id)
        |> Map.new(fn {pid, items} -> {pid, length(items)} end)

      examples =
        matching_items
        |> Enum.take(5)
        |> Enum.map(& &1.prompt)

      Ash.create!(PromptPattern, %{
        run_id: run.id,
        needle: needle,
        label: pattern["label"],
        count_total: count_total,
        project_counts: project_counts,
        examples: %{"items" => examples},
        confidence: pattern["confidence"]
      })
    end)
  end

  defp create_run!(scope, project_id, timespan_days, prompt_limit, max_prompt_chars) do
    Ash.create!(PromptPatternRun, %{
      scope: scope,
      project_id: project_id,
      timespan_days: timespan_days,
      prompt_limit: prompt_limit,
      max_prompt_chars: max_prompt_chars,
      status: :queued
    })
  end

  defp mark_running!(run) do
    Ash.update!(run, %{}, action: :mark_running)
  end

  defp complete_run!(run, meta, model_used) do
    Ash.update!(
      run,
      %{
        prompts_total: meta.prompts_total,
        prompts_analyzed: meta.prompts_analyzed,
        unique_prompts: meta.unique_prompts,
        model_used: model_used
      },
      action: :complete
    )
  end

  defp fail_run(run, error_msg) do
    Ash.update!(run, %{error: error_msg}, action: :fail)
  end

  defp parse_scope("project"), do: :project
  defp parse_scope(_), do: :global

  defp agent_module do
    Application.get_env(
      :spotter,
      :prompt_pattern_agent_module,
      Spotter.Services.PromptPatternAgent
    )
  end
end
