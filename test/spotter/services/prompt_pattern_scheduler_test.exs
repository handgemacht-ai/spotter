defmodule Spotter.Services.PromptPatternSchedulerTest do
  use Spotter.DataCase

  alias Spotter.Services.PromptPatternScheduler

  describe "schedule_auto_run_if_ready/0 (disabled)" do
    test "returns :disabled" do
      assert :disabled = PromptPatternScheduler.schedule_auto_run_if_ready()
    end
  end

  describe "sessions_remaining_for_auto_run/0 (disabled)" do
    test "returns 0" do
      assert PromptPatternScheduler.sessions_remaining_for_auto_run() == 0
    end
  end

  describe "run_progress_for_ui/0 (disabled)" do
    test "returns disabled payload" do
      progress = PromptPatternScheduler.run_progress_for_ui()

      assert progress.remaining == 0
      assert progress.cadence == 0
      assert progress.latest_status == :disabled
    end
  end
end
