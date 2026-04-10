defmodule Spotter.Application do
  @moduledoc false

  use Application

  alias Spotter.Beads.DoltStore
  alias Spotter.Observability.ObanTelemetry
  alias Spotter.Observability.ParallelLanesTelemetry
  alias Spotter.Telemetry.Otel
  alias SpotterWeb.Telemetry.LiveviewOtel

  @impl true
  def start(_type, _args) do
    :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
      config: %{metadata: [:file, :line]}
    })

    # Initialize OpenTelemetry before starting children
    Otel.setup()
    LiveviewOtel.setup()
    ObanTelemetry.setup()
    ParallelLanesTelemetry.setup()

    children =
      [
        {Registry, keys: :unique, name: Spotter.Beads.JsonlStore.Registry},
        {DynamicSupervisor, name: Spotter.Beads.JsonlStore.Supervisor, strategy: :one_for_one},
        {Phoenix.PubSub, name: Spotter.PubSub},
        Spotter.Services.TranscriptFileLinks,
        Spotter.Observability.FlowHub,
        {Registry, keys: :unique, name: Spotter.Services.TranscriptTailRegistry},
        Spotter.Services.TranscriptTailSupervisor,
        {Registry, keys: :unique, name: Spotter.Beads.DoltStore.Registry},
        dolt_store_supervisor(),
        Spotter.Repo,
        {Oban,
         AshOban.config(
           Application.fetch_env!(:spotter, :ash_domains),
           Application.fetch_env!(:spotter, Oban)
         )},
        SpotterWeb.Endpoint
      ]

    opts = [strategy: :one_for_one, name: Spotter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp dolt_store_supervisor do
    children =
      DoltStore.configured_projects()
      |> Enum.map(&DoltStore.child_spec/1)

    %{
      id: DoltStore.Supervisor,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
    }
  end
end
