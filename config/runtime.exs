import Config

# Waiting overlay summary configuration
# SPOTTER_SUMMARY_MODEL - LLM model for summaries (default: claude-3-5-haiku-latest)
# SPOTTER_SUMMARY_TOKEN_BUDGET - character budget for transcript slicing (default: 4000)
# SPOTTER_WAITING_DELAY_SECONDS - delay before showing overlay (default: 300)
# SPOTTER_OVERLAY_HEIGHT - tmux popup height in lines (default: 16)
# SPOTTER_ANTHROPIC_API_KEY - required for LLM-based summaries
#
# Session distillation configuration
# SPOTTER_SESSION_DISTILL_MODEL - LLM model for session distillation (default: claude-3-5-haiku-latest)
# SPOTTER_SESSION_DISTILL_INPUT_CHAR_BUDGET - char budget for transcript slice (default: 30000)
# SPOTTER_DISTILL_TIMEOUT_MS - Session distillation timeout in ms (default: 45000)
#
# Project rollup configuration
# SPOTTER_PROJECT_ROLLUP_MODEL - LLM model for project rollups (default: claude-3-5-haiku-latest)
# SPOTTER_PROJECT_ROLLUP_DISTILL_TIMEOUT_MS - Project rollup distillation timeout in ms (default: 45000)
# SPOTTER_ROLLUP_BUCKET_KIND - bucket granularity: day, week, or month (default: week)
# SPOTTER_ROLLUP_LOOKBACK_DAYS - rolling summary lookback window in days (default: 30)

# Product Spec (Dolt) configuration
config :spotter, Spotter.ProductSpec.Repo,
  hostname: System.get_env("SPOTTER_DOLT_HOST", "localhost"),
  port: String.to_integer(System.get_env("SPOTTER_DOLT_PORT", "13307")),
  database: System.get_env("SPOTTER_DOLT_DATABASE", "spotter_product"),
  username: System.get_env("SPOTTER_DOLT_USERNAME", "spotter"),
  password: System.get_env("SPOTTER_DOLT_PASSWORD", "spotter"),
  pool_size: 5

# Test Spec (Dolt) configuration — falls back to product-spec Dolt values when unset
config :spotter, Spotter.TestSpec.Repo,
  hostname:
    System.get_env(
      "SPOTTER_TEST_SPEC_DOLT_HOST",
      System.get_env("SPOTTER_DOLT_HOST", "localhost")
    ),
  port:
    String.to_integer(
      System.get_env(
        "SPOTTER_TEST_SPEC_DOLT_PORT",
        System.get_env("SPOTTER_DOLT_PORT", "13307")
      )
    ),
  database:
    System.get_env(
      "SPOTTER_TEST_SPEC_DOLT_DATABASE",
      "spotter_tests"
    ),
  username:
    System.get_env(
      "SPOTTER_TEST_SPEC_DOLT_USERNAME",
      System.get_env("SPOTTER_DOLT_USERNAME", "spotter")
    ),
  password:
    System.get_env(
      "SPOTTER_TEST_SPEC_DOLT_PASSWORD",
      System.get_env("SPOTTER_DOLT_PASSWORD", "spotter")
    ),
  pool_size:
    (case System.get_env("SPOTTER_TEST_SPEC_POOL_SIZE") do
       nil ->
         5

       val ->
         case Integer.parse(val) do
           {n, _} when n > 0 -> n
           _ -> 5
         end
     end)

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
