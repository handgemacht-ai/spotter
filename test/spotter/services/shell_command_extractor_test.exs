defmodule Spotter.Services.ShellCommandExtractorTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Services.ShellCommandExtractor
  alias Spotter.Transcripts.{Project, Session, ShellCommandEvent}

  setup do
    Sandbox.checkout(Spotter.Repo)

    project = Ash.create!(Project, %{name: "extractor-test", pattern: "^extractor-test$"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        project_id: project.id,
        cwd: "/home/user/extractor-test"
      })

    %{project: project, session: session}
  end

  describe "extract_commands/1" do
    test "extracts command from top-level tool_input" do
      payload = %{
        "tool_input" => %{"command" => "mix test"},
        "tool_name" => "Bash"
      }

      assert [{"mix test", "tool_input.command"}] =
               ShellCommandExtractor.extract_commands(payload)
    end

    test "extracts multiple commands from nested payload" do
      payload = %{
        "tool_input" => %{"command" => "ls -la"},
        "nested" => %{"deep" => %{"command" => "git status"}}
      }

      result = ShellCommandExtractor.extract_commands(payload)
      commands = Enum.map(result, &elem(&1, 0))
      assert "ls -la" in commands
      assert "git status" in commands
    end

    test "extracts commands from lists" do
      payload = %{
        "items" => [
          %{"command" => "echo hello"},
          %{"command" => "echo world"}
        ]
      }

      result = ShellCommandExtractor.extract_commands(payload)
      assert length(result) == 2
      commands = Enum.map(result, &elem(&1, 0))
      assert "echo hello" in commands
      assert "echo world" in commands
    end

    test "ignores non-string command values" do
      payload = %{
        "command" => 42,
        "tool_input" => %{"command" => "valid"}
      }

      result = ShellCommandExtractor.extract_commands(payload)
      assert [{"valid", "tool_input.command"}] = result
    end

    test "returns empty list for payload without commands" do
      payload = %{
        "tool_name" => "Write",
        "tool_input" => %{"file_path" => "/tmp/test.txt"}
      }

      assert [] = ShellCommandExtractor.extract_commands(payload)
    end

    test "returns empty list for non-map input" do
      assert [] = ShellCommandExtractor.extract_commands("not a map")
      assert [] = ShellCommandExtractor.extract_commands(nil)
    end
  end

  describe "extract_and_persist/2" do
    test "creates shell command event for PreToolUse Bash command", %{session: session} do
      payload = %{
        "session_id" => session.session_id,
        "hook_event_name" => "PreToolUse",
        "tool_name" => "Bash",
        "tool_use_id" => "toolu_pre_123",
        "tool_input" => %{"command" => "mix test"}
      }

      assert {:ok, 1, _project_id} =
               ShellCommandExtractor.extract_and_persist(payload, "raw-event-1")

      events = Ash.read!(ShellCommandEvent)
      assert length(events) == 1
      event = hd(events)
      assert event.command == "mix test"
      assert event.phase == :start
      assert event.finish_status == nil
      assert event.session_id == session.id
      assert event.project_id == session.project_id
      assert event.external_session_id == session.session_id
      assert event.tool_use_id == "toolu_pre_123"
    end

    test "creates shell command event for PostToolUse with :ok status", %{session: session} do
      payload = %{
        "session_id" => session.session_id,
        "hook_event_name" => "PostToolUse",
        "tool_name" => "Bash",
        "tool_use_id" => "toolu_post_123",
        "tool_input" => %{"command" => "mix test"}
      }

      assert {:ok, 1, _} = ShellCommandExtractor.extract_and_persist(payload, "raw-event-2")

      event = Ash.read_one!(ShellCommandEvent)
      assert event.phase == :finish
      assert event.finish_status == :ok
    end

    test "creates shell command event for PostToolUseFailure with :error status", %{
      session: session
    } do
      payload = %{
        "session_id" => session.session_id,
        "hook_event_name" => "PostToolUseFailure",
        "tool_name" => "Bash",
        "tool_use_id" => "toolu_fail_123",
        "tool_input" => %{"command" => "false"}
      }

      assert {:ok, 1, _} = ShellCommandExtractor.extract_and_persist(payload, "raw-event-3")

      event = Ash.read_one!(ShellCommandEvent)
      assert event.phase == :finish
      assert event.finish_status == :error
    end

    test "skips non-tool events like SessionStart", %{session: session} do
      payload = %{
        "session_id" => session.session_id,
        "hook_event_name" => "SessionStart",
        "tool_input" => %{"command" => "should not persist"}
      }

      assert {:ok, 0, _} = ShellCommandExtractor.extract_and_persist(payload, "raw-event-4")
      assert [] = Ash.read!(ShellCommandEvent)
    end

    test "skips payloads without command keys", %{session: session} do
      payload = %{
        "session_id" => session.session_id,
        "hook_event_name" => "PostToolUse",
        "tool_name" => "Write",
        "tool_use_id" => "toolu_write_123",
        "tool_input" => %{"file_path" => "/tmp/test.txt", "content" => "hello"}
      }

      assert {:ok, 0, _} = ShellCommandExtractor.extract_and_persist(payload, "raw-event-5")
    end

    test "creates multiple events for multiple commands", %{session: session} do
      payload = %{
        "session_id" => session.session_id,
        "hook_event_name" => "PreToolUse",
        "tool_name" => "Bash",
        "tool_use_id" => "toolu_multi_123",
        "tool_input" => %{"command" => "ls"},
        "nested" => %{"command" => "pwd"}
      }

      assert {:ok, 2, _} = ShellCommandExtractor.extract_and_persist(payload, "raw-event-6")
      assert length(Ash.read!(ShellCommandEvent)) == 2
    end

    test "deduplicates on upsert identity", %{session: session} do
      payload = %{
        "session_id" => session.session_id,
        "hook_event_name" => "PreToolUse",
        "tool_name" => "Bash",
        "tool_use_id" => "toolu_dup_123",
        "tool_input" => %{"command" => "echo dup"}
      }

      assert {:ok, 1, _} = ShellCommandExtractor.extract_and_persist(payload, "raw-event-7")
      assert {:ok, 1, _} = ShellCommandExtractor.extract_and_persist(payload, "raw-event-7")

      assert length(Ash.read!(ShellCommandEvent)) == 1
    end

    test "never raises on failure" do
      assert {:ok, 0, nil} = ShellCommandExtractor.extract_and_persist(nil, "raw-event-8")
    end
  end
end
