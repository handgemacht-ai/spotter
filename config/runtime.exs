import Config

# Waiting overlay summary configuration
# SPOTTER_SUMMARY_MODEL - LLM model for summaries (default: claude-3-5-haiku-latest)
# SPOTTER_SUMMARY_TOKEN_BUDGET - character budget for transcript slicing (default: 4000)
# SPOTTER_WAITING_DELAY_SECONDS - delay before showing overlay (default: 300)
# SPOTTER_OVERLAY_HEIGHT - tmux popup height in lines (default: 16)
# ANTHROPIC_API_KEY - required for LLM-based summaries

if config_env() == :prod do
  config :spotter, Spotter.Repo, pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # Configure OpenTelemetry exporter from environment
  # Default to OTLP for production; can be overridden with OTEL_EXPORTER
  exporter = String.to_atom(System.get_env("OTEL_EXPORTER") || "otlp")

  config :opentelemetry,
    span_processor: :batch,
    traces_exporter: exporter

  # OTLP configuration for production
  if exporter == :otlp do
    config :opentelemetry_exporter,
      otlp_protocol: :http_protobuf,
      otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") || "http://localhost:4318"
  end
end
