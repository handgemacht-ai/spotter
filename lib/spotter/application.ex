defmodule Spotter.Application do
  @moduledoc false

  use Application

  alias Spotter.Observability.ObanTelemetry
  alias Spotter.Telemetry.Otel
  alias SpotterWeb.Telemetry.LiveviewOtel

  @impl true
  def start(_type, _args) do
    validate_anthropic_key!()

    # Initialize OpenTelemetry before starting children
    Otel.setup()
    LiveviewOtel.setup()
    ObanTelemetry.setup()

    children =
      [
        {ClaudeAgentSDK.TaskSupervisor, name: Spotter.ClaudeTaskSupervisor},
        {Phoenix.PubSub, name: Spotter.PubSub},
        Spotter.Services.SessionRegistry,
        Spotter.Services.ActiveSessionRegistry,
        Spotter.Services.ReviewSessionRegistry,
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
        Spotter.ProductSpec.Supervisor,
        Spotter.TestSpec.Supervisor
      ]

    opts = [strategy: :one_for_one, name: Spotter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp validate_anthropic_key! do
    env = Application.get_env(:spotter, :env, :prod)

    if env in [:dev, :prod] do
      key = System.get_env("SPOTTER_ANTHROPIC_API_KEY") || ""

      if String.trim(key) == "" do
        raise """
        SPOTTER_ANTHROPIC_API_KEY is required in #{env} environment.

        This key is needed for:
          - Waiting overlay summaries (Spotter.Services.WaitingSummary)
          - Commit hotspot analysis (Spotter.Services.CommitHotspotAgent)
          - Commit test extraction (Spotter.Transcripts.Jobs.AnalyzeCommitTests)

        Export the key before starting the server:

            export SPOTTER_ANTHROPIC_API_KEY=sk-ant-...
            mix phx.server
        """
      end
    end
  end
end
