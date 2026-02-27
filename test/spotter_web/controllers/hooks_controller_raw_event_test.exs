defmodule SpotterWeb.HooksControllerRawEventTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Observability.FlowHub
  alias Spotter.Transcripts.{Project, RawHookEvent, Session}

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

    test "returns 400 for missing session_id in hook_payload" do
      payload = %{
        "hook_payload" => %{
          "hook_event_name" => "PostToolUse",
          "tool_name" => "Write"
        },
        "env" => %{}
      }

      {status, body, _conn} = post_raw_event(payload)

      assert status == 400
      assert body["error"] =~ "session_id is required"
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

      assert ended_session.hook_ended_at != nil
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
end
