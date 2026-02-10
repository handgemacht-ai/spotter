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

  describe "detect_schema_version/1" do
    test "returns 1 for current format" do
      assert JsonlParser.detect_schema_version([]) == 1
    end
  end
end
