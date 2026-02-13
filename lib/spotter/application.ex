defmodule Spotter.Application do
  @moduledoc false

  use Application

  alias Spotter.Telemetry.Otel
  alias SpotterWeb.Telemetry.LiveviewOtel

  @impl true
  def start(_type, _args) do
    validate_anthropic_key!()

    # Initialize OpenTelemetry before starting children
    Otel.setup()
    LiveviewOtel.setup()

    children =
      [
        ClaudeAgentSDK.TaskSupervisor,
        {Phoenix.PubSub, name: Spotter.PubSub},
        Spotter.Services.SessionRegistry,
        Spotter.Services.ActiveSessionRegistry,
        Spotter.Services.ReviewSessionRegistry,
        Spotter.Services.ReviewTokenStore,
        Spotter.Observability.FlowHub,
        {Registry, keys: :unique, name: Spotter.Services.TranscriptTailRegistry},
        Spotter.Services.TranscriptTailSupervisor,
        Spotter.Repo,
        {Oban,
         AshOban.config(
           Application.fetch_env!(:spotter, :ash_domains),
           Application.fetch_env!(:spotter, Oban)
         )},
        SpotterWeb.Endpoint,
        Spotter.ProductSpec.Supervisor
      ]

    opts = [strategy: :one_for_one, name: Spotter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp validate_anthropic_key! do
    env = Application.get_env(:spotter, :env, :prod)

    if env in [:dev, :prod] do
      key = System.get_env("ANTHROPIC_API_KEY") || ""

      if String.trim(key) == "" do
        raise """
        ANTHROPIC_API_KEY is required in #{env} environment.

        This key is needed for:
          - Waiting overlay summaries (Spotter.Services.WaitingSummary)
          - Commit hotspot analysis (Spotter.Services.CommitHotspotAgent)

        Export the key before starting the server:

            export ANTHROPIC_API_KEY=sk-ant-...
            mix phx.server
        """
      end
    end
  end
end
