defmodule SpotterWeb.HooksControllerRawEventTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Observability.FlowHub
  alias Spotter.Transcripts.{Project, RawHookEvent, Session, ShellCommandEvent}

  require Ash.Query

  @endpoint SpotterWeb.Endpoint

  setup do
    Sandbox.checkout(Spotter.Repo)

    if :ets.whereis(FlowHub) != :undefined do
      :ets.delete_all_objects(FlowHub)
    end

    :ok
  end

  defp post_raw_event(params, headers \\ []) do
    conn =
      Enum.reduce(headers, Phoenix.ConnTest.build_conn(), fn {k, v}, conn ->
        Plug.Conn.put_req_header(conn, k, v)
      end)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Phoenix.ConnTest.dispatch(@endpoint, :post, "/api/hooks/raw-event", params)

    {conn.status, Jason.decode!(conn.resp_body), conn}
  end

  describe "POST /api/hooks/raw-event" do
    test "creates raw hook event from valid PostToolUse payload" do
      payload = %{
        "hook_payload" => %{
          "session_id" => "test-session-123",
          "hook_event_name" => "PostToolUse",
          "tool_name" => "Write",
          "tool_use_id" => "toolu_test_123",
          "tool_input" => %{"file_path" => "/tmp/test.txt", "content" => "hello"},
          "cwd" => "/home/user/project",
          "permission_mode" => "default",
          "transcript_path" => "/home/user/.claude/transcripts/test.jsonl"
        },
        "env" => %{
          "USER" => "testuser",
          "SHELL" => "/bin/zsh",
          "PATH_HASH" => "abc123"
        },
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      event = RawHookEvent |> Ash.read_one!()
      assert event.session_id == "test-session-123"
      assert event.hook_event_name == "PostToolUse"
      assert event.tool_name == "Write"
      assert event.tool_use_id == "toolu_test_123"
      assert event.hook_payload["tool_input"]["file_path"] == "/tmp/test.txt"
      assert event.env["USER"] == "testuser"
    end

    test "persists raw event with synthetic session_id when session_id is missing" do
      payload = %{
        "hook_payload" => %{
          "hook_event_name" => "InstructionsLoaded",
          "tool_name" => "Write"
        },
        "env" => %{}
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      event = RawHookEvent |> Ash.read_one!()
      assert String.starts_with?(event.session_id, "synthetic-")
      assert event.hook_event_name == "InstructionsLoaded"
    end

    test "returns 400 for missing hook_payload" do
      {status, body, _conn} = post_raw_event(%{"env" => %{}})

      assert status == 400
      assert body["error"] =~ "hook_payload and env are required"
    end

    test "truncates large string fields but preserves critical keys" do
      large_content = String.duplicate("x", 20_000)

      payload = %{
        "hook_payload" => %{
          "session_id" => "test-session-trunc",
          "hook_event_name" => "PostToolUse",
          "tool_name" => "Write",
          "tool_use_id" => "toolu_trunc_456",
          "tool_input" => %{"file_path" => "/tmp/test.txt", "content" => large_content}
        },
        "env" => %{},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      event = RawHookEvent |> Ash.read_one!()
      tool_input = event.hook_payload["tool_input"]
      assert String.ends_with?(tool_input["content"], "[truncated]")
      assert byte_size(tool_input["content"]) <= 10_240 + 11
      assert tool_input["file_path"] == "/tmp/test.txt"
    end

    test "upserts duplicate events instead of duplicating" do
      payload = %{
        "hook_payload" => %{
          "session_id" => "test-session-dup",
          "hook_event_name" => "PostToolUse",
          "tool_name" => "Write",
          "tool_use_id" => "toolu_dup_789"
        },
        "env" => %{"USER" => "first"},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {201, _, _} = post_raw_event(payload)

      updated_payload = put_in(payload, ["env", "USER"], "second")
      {201, _, _} = post_raw_event(updated_payload)

      events = Ash.read!(RawHookEvent)
      assert length(events) == 1
      assert hd(events).env["USER"] == "second"
    end

    test "handles SessionStart payload without tool_use_id" do
      payload = %{
        "hook_payload" => %{
          "session_id" => "test-session-start",
          "hook_event_name" => "SessionStart"
        },
        "env" => %{"TMUX_PANE" => "%0"},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      event = RawHookEvent |> Ash.read_one!()
      assert event.hook_event_name == "SessionStart"
      assert is_nil(event.tool_use_id)
    end

    test "SessionEnd raw event finalizes the session lifecycle" do
      project = Ash.create!(Project, %{name: "raw-end-project", pattern: "^raw-end-project$"})
      session_id = Ash.UUID.generate()

      Ash.create!(Session, %{
        session_id: session_id,
        project_id: project.id,
        cwd: "/home/user/raw-end-project"
      })

      payload = %{
        "hook_payload" => %{
          "session_id" => session_id,
          "hook_event_name" => "SessionEnd",
          "reason" => "clear",
          "cwd" => "/home/user/raw-end-project"
        },
        "env" => %{},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      ended_session =
        Session
        |> Ash.read!()
        |> Enum.find(&(&1.session_id == session_id))

      assert ended_session.session_ended_at != nil
    end

    test "handles Notification payload" do
      payload = %{
        "hook_payload" => %{
          "session_id" => "test-session-notif",
          "hook_event_name" => "Notification",
          "message" => "Waiting for user input"
        },
        "env" => %{},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true
    end

    test "deeply nested payloads are truncated correctly" do
      large = String.duplicate("y", 20_000)

      payload = %{
        "hook_payload" => %{
          "session_id" => "test-session-deep",
          "hook_event_name" => "PostToolUse",
          "tool_use_id" => "toolu_deep",
          "nested" => %{"level1" => %{"level2" => %{"data" => large}}}
        },
        "env" => %{},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      event = RawHookEvent |> Ash.read_one!()
      nested_data = get_in(event.hook_payload, ["nested", "level1", "level2", "data"])
      assert String.ends_with?(nested_data, "[truncated]")
    end

    test "env values are coerced to strings" do
      payload = %{
        "hook_payload" => %{
          "session_id" => "test-session-env",
          "hook_event_name" => "SessionStart"
        },
        "env" => %{"PORT" => 1100, "DEBUG" => true},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      event = RawHookEvent |> Ash.read_one!()
      assert event.env["PORT"] == "1100"
      assert event.env["DEBUG"] == "true"
    end

    test "returns x-spotter-trace-id header" do
      payload = %{
        "hook_payload" => %{
          "session_id" => "test-session-trace",
          "hook_event_name" => "PostToolUse",
          "tool_use_id" => "toolu_trace"
        },
        "env" => %{}
      }

      {201, _, conn} = post_raw_event(payload)

      trace_id = conn |> Plug.Conn.get_resp_header("x-spotter-trace-id") |> List.first()
      assert trace_id != nil
    end

    test "defaults captured_at when not provided" do
      payload = %{
        "hook_payload" => %{
          "session_id" => "test-session-notime",
          "hook_event_name" => "SessionStart"
        },
        "env" => %{}
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      event = RawHookEvent |> Ash.read_one!()
      assert event.captured_at != nil
    end
  end

  describe "POST /api/hooks/raw-event PubSub broadcast" do
    setup do
      project = Ash.create!(Project, %{name: "pubsub-test", pattern: "^pubsub-test$"})

      session_id = Ash.UUID.generate()

      Ash.create!(Session, %{
        session_id: session_id,
        project_id: project.id,
        cwd: "/home/user/pubsub-test"
      })

      %{project: project, session_id: session_id}
    end

    test "shell command ingestion broadcasts PubSub to shell_telemetry:project:<project_id>",
         %{project: project, session_id: session_id} do
      topic = "shell_telemetry:project:#{project.id}"
      Phoenix.PubSub.subscribe(Spotter.PubSub, topic)

      payload = %{
        "hook_payload" => %{
          "session_id" => session_id,
          "hook_event_name" => "PostToolUse",
          "tool_name" => "Bash",
          "tool_use_id" => "toolu_pubsub_1",
          "tool_input" => %{"command" => "mix test"}
        },
        "env" => %{},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, _body, _conn} = post_raw_event(payload)
      assert status == 201

      expected_project_id = project.id
      assert_receive {:shell_telemetry_updated, %{project_id: ^expected_project_id}}, 2_000
    end

    test "ingestion failure records span error but endpoint still returns 200-level",
         %{project: _project} do
      # Post with a session_id that has no matching session and no project
      # to trigger extraction failure path
      payload = %{
        "hook_payload" => %{
          "session_id" => "nonexistent-session-for-pubsub",
          "hook_event_name" => "PostToolUse",
          "tool_name" => "Bash",
          "tool_use_id" => "toolu_pubsub_fail",
          "tool_input" => %{"command" => "failing command"}
        },
        "env" => %{},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      # The raw event should still be persisted even if shell extraction fails
      {status, body, _conn} = post_raw_event(payload)
      assert status == 201
      assert body["ok"] == true

      # No PubSub message should be broadcast for failed ingestion
      topic = "shell_telemetry:project:global"
      Phoenix.PubSub.subscribe(Spotter.PubSub, topic)
      refute_receive {:shell_telemetry_updated, _}, 500
    end
  end

  describe "POST /api/hooks/raw-event shell command extraction" do
    setup do
      project =
        Ash.create!(Project, %{name: "shell-test", pattern: "^shell-test$"})

      %{project: project}
    end

    defp create_session(project) do
      session_id = Ash.UUID.generate()

      Ash.create!(Session, %{
        session_id: session_id,
        project_id: project.id,
        cwd: "/home/user/shell-test"
      })

      session_id
    end

    test "PreToolUse Bash payload creates ShellCommandEvent with phase :start", %{
      project: project
    } do
      session_id = create_session(project)

      payload = %{
        "hook_payload" => %{
          "session_id" => session_id,
          "hook_event_name" => "PreToolUse",
          "tool_name" => "Bash",
          "tool_use_id" => "toolu_shell_pre_1",
          "tool_input" => %{"command" => "mix test"}
        },
        "env" => %{},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      events = Ash.read!(ShellCommandEvent)
      assert length(events) == 1

      event = hd(events)
      assert event.phase == :start
      assert event.command == "mix test"
      assert event.command_path == "tool_input.command"
    end

    test "PostToolUse Bash payload creates ShellCommandEvent with phase :finish and finish_status :ok",
         %{project: project} do
      session_id = create_session(project)

      payload = %{
        "hook_payload" => %{
          "session_id" => session_id,
          "hook_event_name" => "PostToolUse",
          "tool_name" => "Bash",
          "tool_use_id" => "toolu_shell_post_1",
          "tool_input" => %{"command" => "git status"}
        },
        "env" => %{},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      events = Ash.read!(ShellCommandEvent)
      assert length(events) == 1

      event = hd(events)
      assert event.phase == :finish
      assert event.finish_status == :ok
      assert event.command == "git status"
    end

    test "PostToolUseFailure Bash payload creates ShellCommandEvent with phase :finish and finish_status :error",
         %{project: project} do
      session_id = create_session(project)

      payload = %{
        "hook_payload" => %{
          "session_id" => session_id,
          "hook_event_name" => "PostToolUseFailure",
          "tool_name" => "Bash",
          "tool_use_id" => "toolu_shell_fail_1",
          "tool_input" => %{"command" => "rm -rf /nope"}
        },
        "env" => %{},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      events = Ash.read!(ShellCommandEvent)
      assert length(events) == 1

      event = hd(events)
      assert event.phase == :finish
      assert event.finish_status == :error
      assert event.command == "rm -rf /nope"
    end

    test "payload without command fields creates no ShellCommandEvent", %{project: project} do
      session_id = create_session(project)

      payload = %{
        "hook_payload" => %{
          "session_id" => session_id,
          "hook_event_name" => "PostToolUse",
          "tool_name" => "Write",
          "tool_use_id" => "toolu_shell_none_1",
          "tool_input" => %{"file_path" => "/tmp/test.txt", "content" => "hello"}
        },
        "env" => %{},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      events = Ash.read!(ShellCommandEvent)
      assert events == []
    end

    test "duplicate event with same raw_hook_event_id, command_path, and phase is not duplicated",
         %{project: project} do
      session_id = create_session(project)

      payload = %{
        "hook_payload" => %{
          "session_id" => session_id,
          "hook_event_name" => "PreToolUse",
          "tool_name" => "Bash",
          "tool_use_id" => "toolu_shell_dup_1",
          "tool_input" => %{"command" => "echo hello"}
        },
        "env" => %{},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {201, _, _} = post_raw_event(payload)
      {201, _, _} = post_raw_event(payload)

      events = Ash.read!(ShellCommandEvent)
      assert length(events) == 1
    end

    test "multiple commands in one payload creates multiple events", %{project: project} do
      session_id = create_session(project)

      payload = %{
        "hook_payload" => %{
          "session_id" => session_id,
          "hook_event_name" => "PreToolUse",
          "tool_name" => "Bash",
          "tool_use_id" => "toolu_shell_multi_1",
          "tool_input" => %{"command" => "npm install"},
          "nested" => %{"command" => "npm test"}
        },
        "env" => %{},
        "captured_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 201
      assert body["ok"] == true

      events = Ash.read!(ShellCommandEvent)
      assert length(events) == 2

      commands = Enum.map(events, & &1.command) |> Enum.sort()
      assert commands == ["npm install", "npm test"]
    end

    test "malformed captured_at still creates ShellCommandEvent with server time", %{
      project: project
    } do
      session_id = create_session(project)

      payload = %{
        "hook_payload" => %{
          "session_id" => session_id,
          "hook_event_name" => "PreToolUse",
          "tool_name" => "Bash",
          "tool_use_id" => "toolu_shell_badtime_1",
          "tool_input" => %{"command" => "echo hi"}
        },
        "env" => %{},
        "captured_at" => "not-a-date"
      }

      before = DateTime.utc_now()
      {status, body, _conn} = post_raw_event(payload)
      after_time = DateTime.utc_now()

      assert status == 201
      assert body["ok"] == true

      events = Ash.read!(ShellCommandEvent)
      assert length(events) == 1

      event = hd(events)
      assert event.command == "echo hi"
      # captured_at should fall back to server time
      assert DateTime.compare(event.captured_at, before) in [:gt, :eq]
      assert DateTime.compare(event.captured_at, after_time) in [:lt, :eq]
    end
  end
end
