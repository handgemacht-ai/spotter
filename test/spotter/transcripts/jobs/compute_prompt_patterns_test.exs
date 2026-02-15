defmodule Spotter.Transcripts.Jobs.ComputePromptPatternsTest do
  use Spotter.DataCase

  alias Spotter.Transcripts.Jobs.ComputePromptPatterns
  alias Spotter.Transcripts.{Message, Project, PromptPattern, PromptPatternRun, Session}

  require Ash.Query

  defmodule StubAgent do
    def analyze(prompts, opts) do
      model = Keyword.get(opts, :model, "stub-model")

      patterns =
        if prompts != [] do
          [
            %{
              "needle" => "fix the bug",
              "label" => "Bug fix requests",
              "confidence" => 0.85,
              "examples" => Enum.take(prompts, 3)
            }
          ]
        else
          []
        end

      {:ok, %{model_used: model, patterns: patterns}}
    end
  end

  setup do
    Application.put_env(:spotter, :prompt_pattern_agent_module, StubAgent)

    prev_key = System.get_env("SPOTTER_ANTHROPIC_API_KEY")
    System.put_env("SPOTTER_ANTHROPIC_API_KEY", "test-key-for-stub")

    on_exit(fn ->
      Application.delete_env(:spotter, :prompt_pattern_agent_module)

      if prev_key,
        do: System.put_env("SPOTTER_ANTHROPIC_API_KEY", prev_key),
        else: System.delete_env("SPOTTER_ANTHROPIC_API_KEY")
    end)
  end

  defp create_project do
    Ash.create!(Project, %{
      name: "test-#{System.unique_integer([:positive])}",
      pattern: "^test"
    })
  end

  defp create_session(project) do
    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "test-dir",
      project_id: project.id
    })
  end

  defp create_user_message(session, text) do
    Ash.create!(Message, %{
      uuid: Ash.UUID.generate(),
      type: :user,
      role: :user,
      timestamp: DateTime.utc_now(),
      session_id: session.id,
      content: %{"text" => text}
    })
  end

  describe "perform/1" do
    test "transitions run queued -> running -> completed and persists patterns" do
      project = create_project()
      session = create_session(project)
      create_user_message(session, "fix the bug in login")
      create_user_message(session, "fix the bug in checkout")

      job = build_job(%{"scope" => "global", "timespan_days" => nil})

      assert :ok = ComputePromptPatterns.perform(job)

      runs = Ash.read!(PromptPatternRun)
      assert length(runs) == 1

      [run] = runs
      assert run.status == :completed
      assert run.scope == :global
      assert run.prompts_analyzed == 2
      assert run.model_used != nil
      assert run.started_at != nil
      assert run.completed_at != nil

      patterns = Ash.read!(PromptPattern |> Ash.Query.filter(run_id == ^run.id))
      assert length(patterns) == 1

      [pattern] = patterns
      assert pattern.needle == "fix the bug"
      assert pattern.count_total == 2
      assert pattern.confidence == 0.85
    end

    test "missing API key marks run error without raising" do
      # Clear the API key set by setup so the worker hits the missing_api_key path
      System.delete_env("SPOTTER_ANTHROPIC_API_KEY")

      project = create_project()
      session = create_session(project)
      create_user_message(session, "some prompt")

      job = build_job(%{"scope" => "global", "timespan_days" => nil})

      assert :ok = ComputePromptPatterns.perform(job)

      runs = Ash.read!(PromptPatternRun)
      assert length(runs) == 1

      [run] = runs
      assert run.status == :error
      assert run.error == "missing_api_key"
    end

    test "project scope creates run with correct scope" do
      project = create_project()
      session = create_session(project)
      create_user_message(session, "fix the bug here")

      job =
        build_job(%{
          "scope" => "project",
          "project_id" => project.id,
          "timespan_days" => 7
        })

      # This will fail with missing_api_key if no key is set, which is fine
      # We're testing that the run is created with the correct scope
      assert :ok = ComputePromptPatterns.perform(job)

      runs = Ash.read!(PromptPatternRun)
      assert length(runs) == 1
      [run] = runs
      assert run.scope == :project
      assert run.project_id == project.id
      assert run.timespan_days == 7
    end
  end

  defp build_job(args) do
    %Oban.Job{args: args}
  end
end
