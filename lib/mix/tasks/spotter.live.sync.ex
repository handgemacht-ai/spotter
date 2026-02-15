defmodule Mix.Tasks.Spotter.Live.Sync do
  @moduledoc """
  Triggers a one-shot transcript sync for all configured projects.
  """
  @shortdoc "Sync transcripts for all configured projects"
  use Mix.Task

  alias Spotter.Transcripts.Jobs.SyncTranscripts

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    {:ok, %{run_id: run_id, projects_total: total}} = SyncTranscripts.sync_all()
    Mix.shell().info("Sync complete: run_id=#{run_id}, projects=#{total}")
  end
end
