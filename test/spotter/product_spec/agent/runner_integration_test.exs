defmodule Spotter.ProductSpec.Agent.RunnerIntegrationTest do
  @moduledoc """
  Integration test for the spec agent runner against the live Claude API.

  Requires:
  - SPOTTER_ANTHROPIC_API_KEY set
  - Dolt running: `docker compose -f docker-compose.dolt.yml up -d`
  - Claude Code CLI authenticated (`claude login`)

  Run with: mix test test/spotter/product_spec/agent/runner_integration_test.exs --include live_api
  """

  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Spotter.ProductSpec.Agent.Runner
  alias Spotter.ProductSpec.Repo
  alias Spotter.ProductSpec.Schema

  @moduletag :live_api

  @project_id "00000000-0000-0000-0000-000000000042"

  setup_all do
    # Ensure schema exists (the app supervisor may have started before Dolt was ready)
    Schema.ensure_schema!()
    :ok
  end

  setup do
    # Clean up test data
    SQL.query!(Repo, "DELETE FROM product_requirements WHERE project_id = ?", [@project_id])
    SQL.query!(Repo, "DELETE FROM product_features WHERE project_id = ?", [@project_id])
    SQL.query!(Repo, "DELETE FROM product_domains WHERE project_id = ?", [@project_id])

    :ok
  end

  @tag timeout: 120_000
  test "Runner.run/1 processes a simple commit and invokes tools" do
    input = %{
      project_id: @project_id,
      commit_hash: String.duplicate("b", 40),
      commit_subject: "feat: add user login page with email/password authentication",
      commit_body:
        "Implements a login form with email and password fields, validates credentials against the database, and creates a session on success.",
      diff_stats: %{
        files_changed: 3,
        insertions: 120,
        deletions: 5,
        binary_files: []
      },
      patch_files: [
        %{
          path: "lib/app_web/live/login_live.ex",
          hunks: [
            %{
              header: "@@ -0,0 +1,45 @@",
              new_start: 1,
              new_len: 45,
              lines: [
                "+defmodule AppWeb.LoginLive do",
                "+  use AppWeb, :live_view",
                "+  def mount(_params, _session, socket) do",
                "+    {:ok, assign(socket, form: to_form(%{}))}",
                "+  end",
                "+  def handle_event(\"login\", %{\"email\" => email, \"password\" => password}, socket) do",
                "+    case Accounts.authenticate(email, password) do",
                "+      {:ok, user} -> {:noreply, redirect(socket, to: \"/dashboard\")}",
                "+      {:error, _} -> {:noreply, put_flash(socket, :error, \"Invalid credentials\")}",
                "+    end",
                "+  end",
                "+end"
              ]
            }
          ]
        }
      ],
      context_windows: %{
        "lib/app_web/live/login_live.ex" =>
          "defmodule AppWeb.LoginLive do\n  use AppWeb, :live_view\n  # ... full file content ...\nend"
      }
    }

    assert {:ok, output} = Runner.run(input)
    assert output.ok == true

    # The agent should have at least called domains_list (per prompt instructions)
    tool_names = Enum.map(output.tool_calls, & &1.name)
    assert Enum.any?(tool_names, &String.contains?(&1, "domains_list"))
  end
end
