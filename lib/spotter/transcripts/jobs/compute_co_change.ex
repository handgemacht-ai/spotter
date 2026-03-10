defmodule Spotter.Transcripts.Jobs.ComputeCoChange do
  @moduledoc "Oban worker that computes co-change groups for a project."

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:project_id], period: 30]

  require Logger
  require OpenTelemetry.Tracer

  alias Spotter.Services.CoChangeCalculator

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id}}) do
    if co_change_enabled?() do
      OpenTelemetry.Tracer.with_span "compute_co_change.perform" do
        OpenTelemetry.Tracer.set_attribute("spotter.project_id", project_id)
        Logger.info("ComputeCoChange: computing co-change groups for project #{project_id}")

        :ok = CoChangeCalculator.compute(project_id)
        :ok
      end
    else
      Logger.warning("ComputeCoChange: disabled by configuration, skipping project #{project_id}")
      :ok
    end
  end

  defp co_change_enabled? do
    Application.get_env(:spotter, :co_change_enabled, Mix.env() != :dev)
  end
end
