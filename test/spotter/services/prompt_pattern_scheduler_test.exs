defmodule Spotter.Services.PromptPatternSchedulerTest do
  use Spotter.DataCase

  alias Spotter.Services.PromptPatternScheduler
  alias Spotter.Transcripts.{Project, PromptPatternRun, Session}

  setup do
    project =
      Ash.create!(Project, %{
        name: "scheduler-test-#{System.unique_integer([:positive])}",
        pattern: "^test"
      })

    %{project: project}
  end

  defp create_ended_session(%{project: project}) do
    session_id = Ash.UUID.generate()

    Ash.create!(Session, %{
      session_id: session_id,
      project_id: project.id,
      hook_ended_at: DateTime.utc_now()
    })
  end

  defp create_global_run(status) do
    Ash.create!(PromptPatternRun, %{
      scope: :global,
      project_id: nil,
      prompt_limit: 500,
      max_prompt_chars: 400,
      status: status
    })
  end

  describe "sessions_remaining_for_auto_run/0" do
    test "returns cadence when no ended sessions exist" do
      assert PromptPatternScheduler.sessions_remaining_for_auto_run() > 0
    end

    test "decreases as sessions end", ctx do
      before = PromptPatternScheduler.sessions_remaining_for_auto_run()
      create_ended_session(ctx)
      after_one = PromptPatternScheduler.sessions_remaining_for_auto_run()

      assert after_one == before - 1
    end

    test "returns 0 when threshold is reached", ctx do
      Ash.create!(Spotter.Config.Setting, %{
        key: "prompt_patterns_sessions_per_run",
        value: "2"
      })

      create_ended_session(ctx)
      create_ended_session(ctx)

      assert PromptPatternScheduler.sessions_remaining_for_auto_run() == 0
    end
  end

  describe "schedule_auto_run_if_ready/0" do
    test "returns :not_ready when threshold not met", ctx do
      Ash.create!(Spotter.Config.Setting, %{
        key: "prompt_patterns_sessions_per_run",
        value: "100"
      })

      create_ended_session(ctx)

      assert :not_ready = PromptPatternScheduler.schedule_auto_run_if_ready()
    end

    test "returns :enqueued when threshold is met", ctx do
      Ash.create!(Spotter.Config.Setting, %{
        key: "prompt_patterns_sessions_per_run",
        value: "1"
      })

      create_ended_session(ctx)

      assert :enqueued = PromptPatternScheduler.schedule_auto_run_if_ready()
    end

    test "returns :already_running when latest global run is queued", ctx do
      create_ended_session(ctx)
      create_global_run(:queued)

      assert :already_running = PromptPatternScheduler.schedule_auto_run_if_ready()
    end

    test "returns :already_running when latest global run is running", ctx do
      create_ended_session(ctx)
      create_global_run(:running)

      assert :already_running = PromptPatternScheduler.schedule_auto_run_if_ready()
    end

    test "counts only sessions after last completed run", ctx do
      Ash.create!(Spotter.Config.Setting, %{
        key: "prompt_patterns_sessions_per_run",
        value: "2"
      })

      # Session before the run
      create_ended_session(ctx)
      Process.sleep(10)

      run = create_global_run(:completed)
      Ash.update!(run, %{}, action: :complete)

      # Only 1 session after run, need 2
      Process.sleep(10)
      create_ended_session(ctx)

      assert :not_ready = PromptPatternScheduler.schedule_auto_run_if_ready()

      # Second session after run hits threshold
      Process.sleep(10)
      create_ended_session(ctx)

      assert :enqueued = PromptPatternScheduler.schedule_auto_run_if_ready()
    end
  end

  describe "run_progress_for_ui/0" do
    test "returns progress map with expected keys" do
      progress = PromptPatternScheduler.run_progress_for_ui()

      assert is_integer(progress.remaining)
      assert is_integer(progress.cadence)
      assert progress.cadence > 0
    end

    test "latest_status is nil when no runs exist" do
      progress = PromptPatternScheduler.run_progress_for_ui()

      assert progress.latest_status == nil
    end

    test "latest_status reflects latest run" do
      create_global_run(:completed)

      progress = PromptPatternScheduler.run_progress_for_ui()

      assert progress.latest_status == :completed
    end
  end
end
