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

config :spotter, Spotter.Config.Runtime, transcript_roots: []

# Bound SSE stream duration so GET /api/mcp tests return quickly
config :spotter, SpotterWeb.SpotterMcpPlug,
  sse_keepalive_ms: 10,
  sse_max_duration_ms: 25

# Beads JSONL store — test fixtures
config :spotter, Spotter.Beads.JsonlStore,
  project_paths: %{
    "spotter" => Path.expand("../test/fixtures/beads/spotter/backup", __DIR__)
  }

# Static test fixture data for PlanDetailLive
config :spotter, :plan_detail_test_data, %{
  "beads_spotter/spotter-uok" => %{
    epic: %{
      id: "spotter-uok",
      title: "Plans Navigation",
      status: "open",
      priority: 1,
      issue_type: "epic",
      description: """
      ## Overview

      Plans Navigation feature for Spotter.

      ## Architecture

      ```mermaid
      graph TD
        A[Browser] --> B[LiveView]
        B --> C[BeadQueries]
        C --> D[Dolt DB]
      ```

      ## Acceptance Criteria

      | GIVEN | WHEN | THEN |
      |-------|------|------|
      | A project with epics | User opens plans page | Epic list is displayed |
      | An epic is selected | User clicks epic | Epic detail with children shown |

      ## Classification

      - Type: feature
      - Scope: frontend, backend
      - Complexity: medium

      ## Implementation Notes

      Use MyXQL for Dolt queries.
      """,
      created_at: ~N[2026-03-01 00:00:00],
      updated_at: nil,
      closed_at: nil,
      assignee: nil
    },
    dependencies: [
      %{
        depends_on_id: "spotter-dep-1",
        type: "blocks",
        created_at: ~N[2026-03-01 00:00:00],
        depends_on_title: "Setup Infrastructure",
        depends_on_status: "closed"
      },
      %{
        depends_on_id: "spotter-dep-2",
        type: "discovered-from",
        created_at: ~N[2026-03-01 00:00:00],
        depends_on_title: "Design Spike",
        depends_on_status: "open"
      }
    ],
    children: [
      %{
        id: "spotter-task-1",
        title: "Implement BeadQueries",
        status: "open",
        priority: 2,
        issue_type: "task",
        description: "Query implementation for Dolt database access.",
        created_at: ~N[2026-03-01 00:00:00],
        updated_at: nil,
        closed_at: nil,
        assignee: nil
      },
      %{
        id: "spotter-task-2",
        title: "Create PlanDetailLive",
        status: "in_progress",
        priority: 1,
        issue_type: "task",
        description: "LiveView for epic detail rendering.",
        created_at: ~N[2026-03-02 00:00:00],
        updated_at: nil,
        closed_at: nil,
        assignee: nil
      }
    ],
    graph: %{
      nodes: [
        %{
          id: "spotter-uok",
          title: "Plans Navigation",
          status: "open",
          priority: 1,
          issue_type: "epic"
        },
        %{
          id: "spotter-task-1",
          title: "Implement BeadQueries",
          status: "open",
          priority: 2,
          issue_type: "task"
        },
        %{
          id: "spotter-task-2",
          title: "Create PlanDetailLive",
          status: "in_progress",
          priority: 1,
          issue_type: "task"
        }
      ],
      edges: [
        %{from: "spotter-task-2", to: "spotter-task-1", type: "blocks"}
      ]
    }
  }
}
