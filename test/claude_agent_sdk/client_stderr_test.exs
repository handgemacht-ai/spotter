defmodule ClaudeAgentSDK.ClientStderrTest do
  @moduledoc """
  Regression test: SDK client must not crash on {:transport_stderr, _} messages.

  Before the fix, erlexec transport would send {:transport_stderr, data} to the
  client GenServer, which had no matching handle_info clause, causing a
  FunctionClauseError that terminated the client and cascaded to agent crashes.
  """
  use ExUnit.Case, async: true

  test "handle_info({:transport_stderr, _}) does not crash the client" do
    # Start a bare client GenServer (it won't connect to a real CLI process)
    {:ok, pid} = GenServer.start(ClaudeAgentSDK.Client, %ClaudeAgentSDK.Options{})

    # Subscribe so we can receive the forwarded stderr message
    ref = Process.monitor(pid)

    # Send the problematic message that used to cause FunctionClauseError
    send(
      pid,
      {:transport_stderr,
       "zsh:1: command not found: mcp__spotter-hotspots__repo_read_file_at_commit\n"}
    )

    # Give the GenServer time to process the message
    Process.sleep(50)

    # The client should still be alive (not crashed)
    assert Process.alive?(pid)

    # Clean up
    GenServer.stop(pid, :normal)

    # Ensure we don't get a DOWN message with an error reason
    receive do
      {:DOWN, ^ref, :process, ^pid, reason} ->
        assert reason == :normal
    after
      500 -> flunk("Client did not stop cleanly")
    end
  end

  test "stderr data is forwarded to subscribers as {:claude_stderr, data}" do
    {:ok, pid} = GenServer.start(ClaudeAgentSDK.Client, %ClaudeAgentSDK.Options{})

    # Subscribe to the client
    ClaudeAgentSDK.Client.subscribe(pid)

    stderr_data = "warning: some stderr output\n"
    send(pid, {:transport_stderr, stderr_data})

    assert_receive {:claude_stderr, ^stderr_data}, 500

    GenServer.stop(pid, :normal)
  end
end
