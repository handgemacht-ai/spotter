defmodule Mix.Tasks.Spotter.Live.Sync do
  @moduledoc """
  Triggers a one-shot transcript sync for all configured projects.
  """
  @shortdoc "Sync transcripts for all configured projects"
  use Mix.Task

  alias Spotter.Transcripts.Jobs.SyncTranscripts

  @dialyzer :no_return

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    # Intentional legacy caller — suppress deprecation warning
    # credo:disable-for-lines:3 Credo.Check.Refactor.Apply
    {:ok, %{run_id: run_id, projects_total: total}} =
      apply(SyncTranscripts, :sync_all, [])

    Mix.shell().info("Sync complete: run_id=#{run_id}, projects=#{total}")
  end
end
