import Config

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
