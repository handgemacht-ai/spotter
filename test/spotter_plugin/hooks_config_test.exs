defmodule SpotterPlugin.HooksConfigTest do
  use ExUnit.Case, async: true

  test "notify-session-end runs on SessionEnd and not on Stop" do
    hooks_json_path = Path.join(File.cwd!(), "spotter-plugin/hooks/hooks.json")

    hooks =
      hooks_json_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("hooks")

    stop_commands = commands_for_event(hooks, "Stop")
    session_end_commands = commands_for_event(hooks, "SessionEnd")

    refute "${CLAUDE_PLUGIN_ROOT}/scripts/notify-session-end.sh" in stop_commands
    assert "${CLAUDE_PLUGIN_ROOT}/scripts/notify-session-end.sh" in session_end_commands
    assert "${CLAUDE_PLUGIN_ROOT}/scripts/raw-event-forward.sh" in session_end_commands
  end

  defp commands_for_event(hooks, event_name) do
    hooks
    |> Map.get(event_name, [])
    |> Enum.flat_map(&Map.get(&1, "hooks", []))
    |> Enum.map(&Map.get(&1, "command"))
  end
end
