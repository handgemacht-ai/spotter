import Config

# OpenTelemetry configuration
config :opentelemetry,
  text_map_propagators: [:trace_context, :baggage],
  traces_exporter: :otlp

# Configure Ash to use OpenTelemetry
config :ash,
  tracer: [OpentelemetryAsh]

config :opentelemetry_ash,
  trace_types: [:custom, :action, :flow]

config :ash_oban, pro?: false

config :spotter, Oban,
  engine: Oban.Engines.Lite,
  notifier: Oban.Notifiers.PG,
  queues: [default: 10, spec: 1],
  repo: Spotter.Repo,
  plugins: [
    {Oban.Plugins.Cron, []},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(15)}
  ]

config :spotter, ecto_repos: [Spotter.Repo], ash_domains: [Spotter.Transcripts, Spotter.Config]

config :spotter, SpotterWeb.Endpoint,
  render_errors: [
    formats: [html: SpotterWeb.ErrorHTML, json: SpotterWeb.ErrorJSON],
    layout: false
  ],
  live_view: [signing_salt: "spotter_lv_salt"],
  pubsub_server: Spotter.PubSub

config :ash_json_api,
  show_public_calculations_when_loaded?: false,
  authorize_update_destroy_with_error?: true

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :json_api,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [:json_api, :resources, :policies, :authorization, :domain, :execution]
    ]
  ]

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

# Keep tzdata cache on a writable path in container/dev flows.
config :tzdata, data_dir: System.get_env("SPOTTER_TZDATA_DIR", "/tmp/tzdata")

config :spotter, env: config_env()

import_config "#{config_env()}.exs"
