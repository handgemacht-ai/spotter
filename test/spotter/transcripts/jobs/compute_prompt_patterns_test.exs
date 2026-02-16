defmodule Spotter.Transcripts.Jobs.ComputePromptPatternsTest do
  use Spotter.DataCase

  alias Spotter.Transcripts.Jobs.ComputePromptPatterns
  alias Spotter.Transcripts.{Project, PromptPatternRun, Session}

  require Ash.Query

  defp create_project do
    Ash.create!(Project, %{
      name: "test-#{System.unique_integer([:positive])}",
      pattern: "^test"
    })
  end

  describe "perform/1 (disabled)" do
    test "returns :ok without creating any PromptPatternRun records" do
      project = create_project()

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

      job = %Oban.Job{args: %{"scope" => "global", "timespan_days" => nil}}

      assert :ok = ComputePromptPatterns.perform(job)

      runs = Ash.read!(PromptPatternRun)
      assert runs == []
    end
  end
end
