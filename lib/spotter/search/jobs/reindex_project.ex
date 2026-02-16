defmodule Spotter.Search.Jobs.ReindexProject do
  @moduledoc "Oban worker that reindexes search documents for a project."

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id], period: 30]

  require Logger
  require OpenTelemetry.Tracer

  alias Spotter.Search.Indexer

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    OpenTelemetry.Tracer.with_span "spotter.search.jobs.reindex_project.perform" do
      OpenTelemetry.Tracer.set_attribute("spotter.project_id", project_id)

      Indexer.reindex_project(project_id)
      :ok
    end
  end
end
