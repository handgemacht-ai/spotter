defmodule Spotter.Telemetry.Otel do
  @moduledoc """
  OpenTelemetry bootstrap and configuration for Spotter.

  Provides safe, idempotent initialization of OTEL instrumentation for:
  - Bandit HTTP server
  - Phoenix web framework
  - LiveView interactions
  - Ash domain actions

  Gracefully handles initialization failures and respects the SPOTTER_OTEL_ENABLED
  environment variable for opt-out behavior.
  """

  require Logger

  @doc """
  Initialize OpenTelemetry instrumentation.

  This function is idempotent and never raises. If SPOTTER_OTEL_ENABLED is set to
  "false", OTEL setup is skipped and an info-level log is emitted.

  If initialization fails at runtime, the error is logged at warning level and
  the application continues normally.
  """
  @spec setup() :: :ok
  def setup do
    case System.get_env("SPOTTER_OTEL_ENABLED", "true") do
      "false" ->
        Logger.info("OpenTelemetry disabled via SPOTTER_OTEL_ENABLED=false")
        :ok

      _ ->
        do_setup()
    end
  end

  defp do_setup do
    # Setup Bandit instrumentation
    OpentelemetryBandit.setup([])

    # Setup Phoenix instrumentation with Bandit adapter and LiveView support
    OpentelemetryPhoenix.setup(adapter: :bandit, liveview: true)

    Logger.info("OpenTelemetry instrumentation initialized successfully")
    :ok
  rescue
    error ->
      Logger.warning(
        "OpenTelemetry setup failed: #{Exception.format(:error, error)}. Continuing without tracing."
      )

      :ok
  end
end
