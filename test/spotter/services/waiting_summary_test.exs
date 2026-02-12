defmodule Spotter.Services.WaitingSummaryTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.WaitingSummary

  @fixtures_dir "test/fixtures/transcripts"

  describe "generate/2 with real transcript" do
    test "returns fallback summary for existing transcript (no API key)" do
      path = Path.join(@fixtures_dir, "short.jsonl")

      assert {:ok, result} = WaitingSummary.generate(path)
      assert is_binary(result.summary)
      assert result.summary != ""
      assert is_integer(result.input_chars)
      assert is_map(result.source_window)
      assert Map.has_key?(result.source_window, :head_messages)
      assert Map.has_key?(result.source_window, :tail_messages)
    end

    test "returns error for missing transcript" do
      assert {:error, :transcript_parse_failed} =
               WaitingSummary.generate("/nonexistent/path.jsonl")
    end
  end

  describe "generate/2 with empty transcript" do
    setup do
      path = Path.join(System.tmp_dir!(), "spotter-test-empty-#{System.unique_integer()}.jsonl")
      File.write!(path, "")
      on_exit(fn -> File.rm(path) end)
      %{path: path}
    end

    test "returns result with empty message fallback", %{path: path} do
      assert {:ok, result} = WaitingSummary.generate(path)
      assert is_binary(result.summary)
      assert result.input_chars == 0
    end
  end

  describe "generate/2 with malformed lines" do
    setup do
      path =
        Path.join(System.tmp_dir!(), "spotter-test-malformed-#{System.unique_integer()}.jsonl")

      content = """
      not json at all
      {"type":"user","message":{"role":"user","content":"hello"},"sessionId":"abc123","uuid":"u1","timestamp":"2026-01-01T00:00:00Z"}
      {broken json
      {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]},"sessionId":"abc123","uuid":"u2","timestamp":"2026-01-01T00:00:01Z"}
      """

      File.write!(path, content)
      on_exit(fn -> File.rm(path) end)
      %{path: path}
    end

    test "handles malformed lines gracefully and still produces summary", %{path: path} do
      assert {:ok, result} = WaitingSummary.generate(path)
      assert is_binary(result.summary)
      assert result.input_chars > 0
    end
  end

  describe "generate/2 respects token_budget option" do
    test "uses provided budget" do
      path = Path.join(@fixtures_dir, "short.jsonl")

      assert {:ok, small} = WaitingSummary.generate(path, token_budget: 100)
      assert {:ok, large} = WaitingSummary.generate(path, token_budget: 100_000)

      assert small.input_chars <= large.input_chars
    end
  end

  describe "build_fallback_summary/2" do
    test "includes session id prefix" do
      summary = WaitingSummary.build_fallback_summary("abc12345-full-id", [])
      assert summary =~ "abc12345"
    end

    test "handles nil session_id" do
      summary = WaitingSummary.build_fallback_summary(nil, [])
      assert summary =~ "unknown"
    end

    test "includes message and tool counts" do
      messages = [
        %{type: :user, content: %{"text" => "hi"}},
        %{type: :tool_use, content: %{"blocks" => [%{"type" => "tool_use", "name" => "Bash"}]}},
        %{type: :tool_result, content: %{"text" => "ok"}},
        %{type: :assistant, content: %{"text" => "done"}}
      ]

      summary = WaitingSummary.build_fallback_summary("test-id", messages)
      assert summary =~ "Messages: 4"
      assert summary =~ "Tool calls: 1"
    end

    test "includes last tool action when available" do
      messages = [
        %{
          type: :tool_use,
          content: %{"blocks" => [%{"type" => "tool_use", "name" => "Edit"}]}
        }
      ]

      summary = WaitingSummary.build_fallback_summary("test-id", messages)
      assert summary =~ "Edit"
    end

    test "includes waiting message" do
      summary = WaitingSummary.build_fallback_summary("test", [])
      assert summary =~ "waiting"
    end
  end
end
