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

  describe "notify-session.sh canonical dir export" do
    @tag :tmp_dir
    test "exports SPOTTER_PROJECT_DIR to CLAUDE_ENV_FILE for a git repo", %{tmp_dir: tmp_dir} do
      # Set up a real git repo in the temp dir
      {_, 0} = System.cmd("git", ["init", "--initial-branch=main"], cd: tmp_dir)
      {_, 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: tmp_dir)
      {_, 0} = System.cmd("git", ["config", "user.name", "Test"], cd: tmp_dir)
      {_, 0} = System.cmd("git", ["commit", "--allow-empty", "-m", "init"], cd: tmp_dir)

      env_file = Path.join(tmp_dir, "claude_env")
      File.write!(env_file, "")

      script_path = Path.join(File.cwd!(), "spotter-plugin/scripts/notify-session.sh")
      session_id = "test-#{System.unique_integer([:positive])}"

      input_json = Jason.encode!(%{"session_id" => session_id, "cwd" => tmp_dir})

      test_env = shell_test_env(%{"CLAUDE_ENV_FILE" => env_file, "TMUX_PANE" => "%0"})

      {output, exit_code} =
        System.cmd("bash", ["-c", "echo '#{input_json}' | bash #{script_path}"],
          env: test_env,
          stderr_to_stdout: true
        )

      # Script should exit successfully (or 0 on silent failure)
      assert exit_code == 0, "notify-session.sh exited #{exit_code}:\n#{output}"

      env_contents = File.read!(env_file)

      # Must export SPOTTER_PROJECT_DIR with the canonical (resolved) path
      assert env_contents =~ "SPOTTER_PROJECT_DIR",
             "notify-session.sh must export SPOTTER_PROJECT_DIR to CLAUDE_ENV_FILE"

      # The canonical dir for a normal repo should be the repo root itself
      assert env_contents =~ tmp_dir,
             "SPOTTER_PROJECT_DIR should contain the repo root path"
    end

    @tag :tmp_dir
    test "falls back gracefully when git metadata is unavailable", %{tmp_dir: tmp_dir} do
      # tmp_dir is NOT a git repo — no .git directory
      non_git_dir = Path.join(tmp_dir, "not-a-repo")
      File.mkdir_p!(non_git_dir)

      env_file = Path.join(tmp_dir, "claude_env")
      File.write!(env_file, "")

      script_path = Path.join(File.cwd!(), "spotter-plugin/scripts/notify-session.sh")
      session_id = "test-#{System.unique_integer([:positive])}"

      input_json = Jason.encode!(%{"session_id" => session_id, "cwd" => non_git_dir})

      test_env = shell_test_env(%{"CLAUDE_ENV_FILE" => env_file, "TMUX_PANE" => "%0"})

      {output, exit_code} =
        System.cmd("bash", ["-c", "echo '#{input_json}' | bash #{script_path}"],
          env: test_env,
          stderr_to_stdout: true
        )

      # Script must not fail even when git is unavailable
      assert exit_code == 0, "notify-session.sh exited #{exit_code}:\n#{output}"

      env_contents = File.read!(env_file)

      # Should still export SPOTTER_PROJECT_DIR (falling back to original path)
      assert env_contents =~ "SPOTTER_PROJECT_DIR",
             "notify-session.sh must export SPOTTER_PROJECT_DIR even without git"
    end
  end

  describe "MCP config canonical project dir" do
    test ".mcp.json header uses canonical env var with PWD fallback, not raw PWD" do
      mcp_json_path = Path.join(File.cwd!(), "spotter-plugin/.mcp.json")

      mcp =
        mcp_json_path
        |> File.read!()
        |> Jason.decode!()

      header_value =
        mcp
        |> get_in(["mcpServers", "spotter", "headers", "x-spotter-project-dir"])

      # Must reference a canonical dir env var with fallback, not raw ${PWD}
      assert header_value != "${PWD}",
             "x-spotter-project-dir must use canonical env var, not raw ${PWD}"

      assert header_value =~ "SPOTTER_PROJECT_DIR",
             "x-spotter-project-dir must reference SPOTTER_PROJECT_DIR env var"

      # Must include a safe fallback to ${PWD} when the canonical var is unset
      assert header_value =~ "${PWD}",
             "x-spotter-project-dir must fall back to ${PWD} when canonical var is unset"
    end
  end

  defp shell_test_env(extra) do
    essential_paths = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    System.get_env()
    |> Map.merge(extra)
    |> Map.merge(%{
      "SPOTTER_SESSION_ID" => nil,
      "SPOTTER_PROJECT_DIR" => nil,
      "CLAUDE_PLUGIN_ROOT" => nil
    })
    |> Map.update("PATH", essential_paths, fn path ->
      if String.contains?(path, "/usr/bin") do
        path
      else
        path <> ":" <> essential_paths
      end
    end)
    |> Enum.to_list()
  end

  defp commands_for_event(hooks, event_name) do
    hooks
    |> Map.get(event_name, [])
    |> Enum.flat_map(&Map.get(&1, "hooks", []))
    |> Enum.map(&Map.get(&1, "command"))
  end
end
