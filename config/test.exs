import Config

# Use simple processor in tests so individual tests can capture spans via
# :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
config :opentelemetry,
  traces_exporter: :none,
  processors: [
    {:otel_simple_processor, %{exporter: {:otel_exporter_pid, :undefined}}}
  ]

# Disable Ash auto-tracing in tests to prevent OTel simple processor contention
# (Ash spans serialize exports and block manual span assertions)
config :ash, tracer: []

config :spotter, Oban, testing: :manual
config :logger, level: :warning

config :spotter, Spotter.Repo,
  database: Path.join(__DIR__, "../path/to/your#{System.get_env("MIX_TEST_PARTITION")}.db"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :spotter, SpotterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test-only-secret-base-minimum-64-bytes-long-enough-for-phoenix-token-signing-ok",
  server: false

config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Bound SSE stream duration so GET /api/mcp tests return quickly
config :spotter, SpotterWeb.SpotterMcpPlug,
  sse_keepalive_ms: 10,
  sse_max_duration_ms: 25
