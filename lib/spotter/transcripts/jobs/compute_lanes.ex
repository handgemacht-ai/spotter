defmodule Spotter.Transcripts.Jobs.ComputeLanes do
  @moduledoc """
  Oban worker that pre-computes and caches lane data for a team.

  Triggered after transcript sync when team membership is established.
  The cached result makes opening the lanes view an instant DB read
  instead of an expensive re-computation.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:team_id], period: 30]

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Transcripts.ParallelLanes

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"team_id" => team_id}}) do
    Tracer.with_span "spotter.compute_lanes.perform" do
      Tracer.set_attribute("spotter.team_id", team_id)
      Logger.info("ComputeLanes: computing lanes for team #{team_id}")

      case ParallelLanes.compute_and_cache(team_id) do
        {:ok, _result} ->
          Logger.info("ComputeLanes: cached lanes for team #{team_id}")
          :ok

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          Logger.warning("ComputeLanes: failed for team #{team_id}: #{inspect(reason)}")
          {:error, inspect(reason)}
      end
    end
  end
end
