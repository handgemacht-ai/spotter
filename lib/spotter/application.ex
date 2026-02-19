defmodule Spotter.Application do
  @moduledoc false

  use Application

  alias Spotter.Observability.ObanTelemetry
  alias Spotter.Telemetry.Otel
  alias SpotterWeb.Telemetry.LiveviewOtel

  @impl true
  def start(_type, _args) do
    # Initialize OpenTelemetry before starting children
    Otel.setup()
    LiveviewOtel.setup()
    ObanTelemetry.setup()

    children =
      [
        {Phoenix.PubSub, name: Spotter.PubSub},
        Spotter.Services.TranscriptFileLinks,
        Spotter.Observability.FlowHub,
        {Registry, keys: :unique, name: Spotter.Services.TranscriptTailRegistry},
        Spotter.Services.TranscriptTailSupervisor,
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
end
