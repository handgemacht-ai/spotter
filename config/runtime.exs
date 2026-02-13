import Config

# Waiting overlay summary configuration
# SPOTTER_SUMMARY_MODEL - LLM model for summaries (default: claude-3-5-haiku-latest)
# SPOTTER_SUMMARY_TOKEN_BUDGET - character budget for transcript slicing (default: 4000)
# SPOTTER_WAITING_DELAY_SECONDS - delay before showing overlay (default: 300)
# SPOTTER_OVERLAY_HEIGHT - tmux popup height in lines (default: 16)
# ANTHROPIC_API_KEY - required for LLM-based summaries
#
# Session distillation configuration
# SPOTTER_SESSION_DISTILL_MODEL - LLM model for session distillation (default: claude-3-5-haiku-latest)
# SPOTTER_SESSION_DISTILL_INPUT_CHAR_BUDGET - char budget for transcript slice (default: 30000)
# SPOTTER_DISTILL_TIMEOUT_MS - LLM call timeout in ms (default: 15000)
#
# Project rollup configuration
# SPOTTER_PROJECT_ROLLUP_MODEL - LLM model for project rollups (default: claude-3-5-haiku-latest)
# SPOTTER_ROLLUP_BUCKET_KIND - bucket granularity: day, week, or month (default: week)
# SPOTTER_ROLLUP_LOOKBACK_DAYS - rolling summary lookback window in days (default: 30)

# LangChain consumes :langchain, :anthropic_key for ChatAnthropic API calls
config :langchain, :anthropic_key, System.get_env("ANTHROPIC_API_KEY")

if config_env() == :prod do
  alias Spotter.Config.EnvParser

  config :spotter, Spotter.Repo, pool_size: EnvParser.parse_pool_size(System.get_env("POOL_SIZE"))

  # Configure OpenTelemetry exporter from environment
  # Default to OTLP for production; can be overridden with OTEL_EXPORTER
  exporter = EnvParser.parse_otel_exporter(System.get_env("OTEL_EXPORTER"))

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
