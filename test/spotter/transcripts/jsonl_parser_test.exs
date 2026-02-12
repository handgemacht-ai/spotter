defmodule Spotter.Transcripts.JsonlParserTest do
  use ExUnit.Case, async: true

  alias Spotter.Transcripts.JsonlParser

  @fixtures_dir Path.join(__DIR__, "fixtures")

  setup do
    File.mkdir_p!(@fixtures_dir)

    session_file = Path.join(@fixtures_dir, "test_session.jsonl")

    lines = [
      Jason.encode!(%{
        "uuid" => "msg-1",
        "type" => "system",
        "sessionId" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        "slug" => "test-session",
        "cwd" => "/tmp/test",
        "gitBranch" => "main",
        "version" => "2.1.38",
        "timestamp" => "2026-01-01T00:00:00.000Z",
        "message" => %{"role" => "system", "content" => "Hello"}
      }),
      Jason.encode!(%{
        "uuid" => "msg-2",
        "type" => "user",
        "parentUuid" => "msg-1",
        "timestamp" => "2026-01-01T00:01:00.000Z",
        "message" => %{"role" => "user", "content" => "Test message"}
      }),
      Jason.encode!(%{
        "uuid" => "msg-3",
        "type" => "assistant",
        "parentUuid" => "msg-2",
        "timestamp" => "2026-01-01T00:02:00.000Z",
        "message" => %{
          "role" => "assistant",
          "content" => [%{"type" => "text", "text" => "Response"}]
        }
      })
    ]

    File.write!(session_file, Enum.join(lines, "\n"))

    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)

    %{session_file: session_file}
  end

  describe "parse_session_file/1" do
    test "parses valid session file", %{session_file: file} do
      assert {:ok, result} = JsonlParser.parse_session_file(file)

      assert result.session_id == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
      assert result.slug == "test-session"
      assert result.cwd == "/tmp/test"
      assert result.git_branch == "main"
      assert result.version == "2.1.38"
      assert result.schema_version == 1
      assert length(result.messages) == 3
    end

    test "returns error for missing file" do
      assert {:error, :file_not_found} = JsonlParser.parse_session_file("/nonexistent.jsonl")
    end

    test "extracts content as map", %{session_file: file} do
      {:ok, result} = JsonlParser.parse_session_file(file)

      # String content becomes %{"text" => ...}
      system_msg = Enum.at(result.messages, 0)
      assert %{"text" => "Hello"} = system_msg.content

      # Array content becomes %{"blocks" => [...]}
      assistant_msg = Enum.at(result.messages, 2)
      assert %{"blocks" => [%{"type" => "text", "text" => "Response"}]} = assistant_msg.content
    end

    test "retains raw_payload for each normalized message", %{session_file: file} do
      {:ok, result} = JsonlParser.parse_session_file(file)

      [first | _] = result.messages
      assert is_map(first.raw_payload)
      assert first.raw_payload["uuid"] == "msg-1"
      assert first.raw_payload["sessionId"] == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    end

    test "parses file-history-snapshot message type variant" do
      file = Path.join(@fixtures_dir, "file_history_snapshot_alias.jsonl")

      File.write!(
        file,
        Jason.encode!(%{
          "uuid" => "msg-1",
          "type" => "file-history-snapshot",
          "sessionId" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
          "timestamp" => "2026-01-01T00:00:00.000Z"
        })
      )

      {:ok, result} = JsonlParser.parse_session_file(file)
      assert [message] = result.messages
      assert message.type == :file_history_snapshot
    end
  end

  describe "parse_subagent_file/1" do
    test "extracts agent_id from filename" do
      file = Path.join(@fixtures_dir, "agent-abc123.jsonl")

      File.write!(
        file,
        Jason.encode!(%{
          "uuid" => "x",
          "type" => "system",
          "timestamp" => "2026-01-01T00:00:00.000Z"
        })
      )

      assert {:ok, result} = JsonlParser.parse_subagent_file(file)
      assert result.agent_id == "abc123"
    end
  end

  describe "timestamp fallback" do
    test "started_at uses first non-nil timestamp when first line has none" do
      file = Path.join(@fixtures_dir, "ts_fallback.jsonl")

      lines = [
        # First line: file_history_snapshot with no timestamp
        Jason.encode!(%{
          "uuid" => "msg-1",
          "type" => "file_history_snapshot",
          "sessionId" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        }),
        # Second line: has a timestamp
        Jason.encode!(%{
          "uuid" => "msg-2",
          "type" => "user",
          "timestamp" => "2026-01-15T10:00:00.000Z",
          "message" => %{"role" => "user", "content" => "Hello"}
        }),
        # Third line: has a later timestamp
        Jason.encode!(%{
          "uuid" => "msg-3",
          "type" => "assistant",
          "timestamp" => "2026-01-15T10:05:00.000Z",
          "message" => %{"role" => "assistant", "content" => "Hi"}
        })
      ]

      File.write!(file, Enum.join(lines, "\n"))

      {:ok, result} = JsonlParser.parse_session_file(file)

      assert result.started_at == ~U[2026-01-15 10:00:00.000Z]
      assert result.ended_at == ~U[2026-01-15 10:05:00.000Z]
    end

    test "started_at and ended_at are nil when all timestamps are nil" do
      file = Path.join(@fixtures_dir, "no_timestamps.jsonl")

      lines = [
        Jason.encode!(%{
          "uuid" => "msg-1",
          "type" => "file_history_snapshot",
          "sessionId" => "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        }),
        Jason.encode!(%{
          "uuid" => "msg-2",
          "type" => "system"
        })
      ]

      File.write!(file, Enum.join(lines, "\n"))

      {:ok, result} = JsonlParser.parse_session_file(file)

      assert result.started_at == nil
      assert result.ended_at == nil
    end
  end

  describe "detect_schema_version/1" do
    test "returns 1 for current format" do
      assert JsonlParser.detect_schema_version([]) == 1
    end
  end

  describe "extract_session_rework_records/2" do
    defp write_msg(tool_use_id, file_path) do
      %{
        uuid: "msg-#{tool_use_id}",
        type: :assistant,
        role: :assistant,
        timestamp: ~U[2026-02-12 10:00:00Z],
        content: %{
          "blocks" => [
            %{
              "type" => "tool_use",
              "id" => tool_use_id,
              "name" => "Write",
              "input" => %{"file_path" => file_path}
            }
          ]
        }
      }
    end

    defp edit_msg(tool_use_id, file_path) do
      %{
        uuid: "msg-#{tool_use_id}",
        type: :assistant,
        role: :assistant,
        timestamp: ~U[2026-02-12 10:01:00Z],
        content: %{
          "blocks" => [
            %{
              "type" => "tool_use",
              "id" => tool_use_id,
              "name" => "Edit",
              "input" => %{"file_path" => file_path}
            }
          ]
        }
      }
    end

    defp success_result(tool_use_id) do
      %{
        uuid: "result-#{tool_use_id}",
        type: :tool_result,
        role: :user,
        timestamp: ~U[2026-02-12 10:00:01Z],
        content: %{
          "blocks" => [
            %{"type" => "tool_result", "tool_use_id" => tool_use_id, "content" => "OK"}
          ]
        }
      }
    end

    defp error_result(tool_use_id) do
      %{
        uuid: "result-#{tool_use_id}",
        type: :tool_result,
        role: :user,
        timestamp: ~U[2026-02-12 10:00:01Z],
        content: %{
          "blocks" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => tool_use_id,
              "is_error" => true,
              "content" => "Permission denied"
            }
          ]
        }
      }
    end

    test "produces rework records for 2nd+ successful modification of same file" do
      messages = [
        write_msg("tu-1", "/home/user/project/lib/foo.ex"),
        success_result("tu-1"),
        edit_msg("tu-2", "/home/user/project/lib/foo.ex"),
        success_result("tu-2"),
        edit_msg("tu-3", "/home/user/project/lib/foo.ex"),
        success_result("tu-3")
      ]

      records = JsonlParser.extract_session_rework_records(messages)

      assert length(records) == 2
      [r1, r2] = records
      assert r1.tool_use_id == "tu-2"
      assert r1.occurrence_index == 2
      assert r1.first_tool_use_id == "tu-1"
      assert r2.tool_use_id == "tu-3"
      assert r2.occurrence_index == 3
      assert r2.first_tool_use_id == "tu-1"
    end

    test "ignores failed tool results" do
      messages = [
        write_msg("tu-1", "/home/user/project/lib/foo.ex"),
        success_result("tu-1"),
        edit_msg("tu-2", "/home/user/project/lib/foo.ex"),
        error_result("tu-2"),
        edit_msg("tu-3", "/home/user/project/lib/foo.ex"),
        success_result("tu-3")
      ]

      records = JsonlParser.extract_session_rework_records(messages)

      assert length(records) == 1
      [r1] = records
      assert r1.tool_use_id == "tu-3"
      assert r1.occurrence_index == 2
    end

    test "different files do not count as rework" do
      messages = [
        write_msg("tu-1", "/project/lib/foo.ex"),
        success_result("tu-1"),
        write_msg("tu-2", "/project/lib/bar.ex"),
        success_result("tu-2")
      ]

      records = JsonlParser.extract_session_rework_records(messages)
      assert records == []
    end

    test "normalizes paths using session_cwd" do
      messages = [
        write_msg("tu-1", "/home/user/project/lib/foo.ex"),
        success_result("tu-1"),
        edit_msg("tu-2", "/home/user/project/lib/foo.ex"),
        success_result("tu-2")
      ]

      records =
        JsonlParser.extract_session_rework_records(messages,
          session_cwd: "/home/user/project"
        )

      assert length(records) == 1
      [r1] = records
      assert r1.file_path == "/home/user/project/lib/foo.ex"
      assert r1.relative_path == "lib/foo.ex"
    end

    test "returns empty list for single modification per file" do
      messages = [
        write_msg("tu-1", "/project/lib/foo.ex"),
        success_result("tu-1")
      ]

      assert JsonlParser.extract_session_rework_records(messages) == []
    end

    test "sets detection_source to :transcript_sync" do
      messages = [
        write_msg("tu-1", "/project/lib/foo.ex"),
        success_result("tu-1"),
        edit_msg("tu-2", "/project/lib/foo.ex"),
        success_result("tu-2")
      ]

      [record] = JsonlParser.extract_session_rework_records(messages)
      assert record.detection_source == :transcript_sync
    end
  end
end
