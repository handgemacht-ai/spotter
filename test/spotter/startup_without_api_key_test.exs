defmodule Spotter.StartupWithoutApiKeyTest do
  @moduledoc """
  Verifies that Spotter boots and runs correctly when no Anthropic API key
  is configured. AI-powered features should degrade gracefully, not crash.
  """
  use ExUnit.Case, async: true

  describe "application startup without ANTHROPIC_API_KEY" do
    test "all expected supervisor children are running" do
      # Ensure no Anthropic key is set in the test environment
      refute System.get_env("ANTHROPIC_API_KEY"),
             "Test env must not have ANTHROPIC_API_KEY set"

      refute System.get_env("SPOTTER_ANTHROPIC_API_KEY"),
             "Test env must not have SPOTTER_ANTHROPIC_API_KEY set"

      # The app should be fully booted with all supervisor children alive
      children =
        Spotter.Supervisor
        |> Supervisor.which_children()
        |> Enum.map(fn {id, _pid, _type, _modules} -> id end)

      # Use actual registered child IDs from the supervisor
      expected_children = [
        Phoenix.PubSub.Supervisor,
        Spotter.Services.TranscriptFileLinks,
        Spotter.Observability.FlowHub,
        Spotter.Services.TranscriptTailRegistry,
        Spotter.Services.TranscriptTailSupervisor,
        Spotter.Repo,
        Oban,
        SpotterWeb.Endpoint
      ]

      for child <- expected_children do
        assert child in children,
               "Expected #{inspect(child)} to be running in Spotter.Supervisor, " <>
                 "got: #{inspect(children)}"
      end
    end

    test "Oban supervisor is alive and running" do
      refute System.get_env("ANTHROPIC_API_KEY")

      # Find Oban in the supervisor children and verify it's alive
      {Oban, oban_pid, :supervisor, _} =
        Spotter.Supervisor
        |> Supervisor.which_children()
        |> Enum.find(fn {id, _, _, _} -> id == Oban end)

      assert is_pid(oban_pid), "Oban should be running without Anthropic API key"
      assert Process.alive?(oban_pid), "Oban process should be alive"
    end

    test "Phoenix endpoint is serving" do
      refute System.get_env("ANTHROPIC_API_KEY")

      endpoint_pid = Process.whereis(SpotterWeb.Endpoint)
      assert is_pid(endpoint_pid), "SpotterWeb.Endpoint should be running"
      assert Process.alive?(endpoint_pid), "SpotterWeb.Endpoint should be alive"
    end
  end
end
