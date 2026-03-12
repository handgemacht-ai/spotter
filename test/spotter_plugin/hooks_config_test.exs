defmodule SpotterPlugin.HooksConfigTest do
  use ExUnit.Case, async: true

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "spotter-plugin-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    %{tmp_dir: tmp_dir}
  end

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

  describe "spotter_url.sh resolution" do
    test "returns explicit SPOTTER_URL values before localhost" do
      script_path = Path.join(File.cwd!(), "spotter-plugin/scripts/lib/spotter_url.sh")

      {output, 0} =
        System.cmd("bash", ["-lc", ". #{script_path}; spotter_resolve_urls 1100"],
          env:
            shell_test_env(%{
              "SPOTTER_URL" => " http://example.test:1100 , http://other.test:2200 "
            }),
          stderr_to_stdout: true
        )

      assert String.split(output, "\n", trim: true) == [
               "http://example.test:1100",
               "http://other.test:2200",
               "http://localhost:1100"
             ]
    end

    test "ignores deprecated tailscale env vars and falls back to localhost" do
      script_path = Path.join(File.cwd!(), "spotter-plugin/scripts/lib/spotter_url.sh")

      {output, 0} =
        System.cmd("bash", ["-lc", ". #{script_path}; spotter_resolve_urls 1100"],
          env:
            shell_test_env(%{
              "SPOTTER_TAILSCALE_URL" => "http://100.64.0.1:1100",
              "SPOTTER_TAILSCALE_IP" => "100.64.0.2"
            }),
          stderr_to_stdout: true
        )

      assert String.split(output, "\n", trim: true) == ["http://localhost:1100"]
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

  describe "worktree post-create" do
    test "writes preview env values, loopback binding, and localhost MCP config", %{
      tmp_dir: tmp_dir
    } do
      worktree_dir = Path.join(tmp_dir, "Fix DNS")
      worktree_env = Path.join(worktree_dir, ".worktree.env")
      config_dir = Path.join(worktree_dir, "config")

      File.mkdir_p!(config_dir)

      File.write!(
        worktree_env,
        [
          "WORKTREE_NAME='Fix DNS'",
          "SPOTTER_PORT=1104",
          "SPOTTER_PHX_PORT=1104",
          "SPOTTER_DOLT_HOST_PORT=13311",
          "SPOTTER_DOLT_PORT=13311"
        ]
        |> Enum.join("\n")
        |> Kernel.<>("\n")
      )

      script_path = Path.join(File.cwd!(), "scripts/worktree_post_create.sh")

      {output, exit_code} =
        System.cmd("bash", [script_path],
          env:
            shell_test_env(%{
              "WORKTREE_PATH" => worktree_dir,
              "WORKTREE_ENV_FILE" => worktree_env
            }),
          stderr_to_stdout: true
        )

      assert exit_code == 0, "worktree_post_create.sh exited #{exit_code}:\n#{output}"

      env_contents = File.read!(worktree_env)
      assert env_contents =~ "TAILNET_INGRESS_ZONE=dev.handgemacht.internal"
      assert env_contents =~ "PREVIEW_HOST=spotter--fix-dns.dev.handgemacht.internal"
      assert env_contents =~ "PREVIEW_URL=http://spotter--fix-dns.dev.handgemacht.internal"

      dev_local = File.read!(Path.join(config_dir, "dev.local.exs"))
      assert dev_local =~ "http: [ip: {127, 0, 0, 1}, port: 1104]"

      mcp =
        worktree_dir
        |> Path.join(".mcp.json")
        |> File.read!()
        |> Jason.decode!()

      assert get_in(mcp, ["mcpServers", "tidewave", "url"]) ==
               "http://localhost:1104/tidewave/mcp"

      assert File.read!(Path.join(worktree_dir, ".port")) == "1104\n"
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
