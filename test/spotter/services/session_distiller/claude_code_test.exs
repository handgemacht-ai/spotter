defmodule Spotter.Services.SessionDistiller.ClaudeCodeTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.SessionDistiller.ClaudeCode

  @tool_name "mcp__spotter-distill__record_session_distillation"

  defp valid_payload do
    %{
      "session_summary" => "Implemented auth flow",
      "what_changed" => ["Added login endpoint"],
      "commands_run" => ["mix test"],
      "open_threads" => [],
      "risks" => ["No rate limiting"],
      "key_files" => [%{"path" => "lib/auth.ex", "reason" => "Core auth module"}],
      "important_snippets" => [
        %{
          "relative_path" => "lib/auth.ex",
          "line_start" => 10,
          "line_end" => 25,
          "snippet" => "def authenticate(user, pass)",
          "why_important" => "Main auth entry point"
        }
      ],
      "distillation_metadata" => %{
        "confidence" => 0.9,
        "source_sections" => ["transcript"]
      }
    }
  end

  defp tool_result_json(payload) do
    Jason.encode!(%{"ok" => true, "kind" => "session", "payload" => payload})
  end

  defp make_tool_result_message(tool_name, content_text) do
    %{
      type: :tool_result,
      data: %{
        tool_name: tool_name,
        content: [%{"type" => "text", "text" => content_text}]
      }
    }
  end

  defp make_messages_with_tool_result(tool_name, content_text) do
    [
      %{type: :system, data: %{}},
      %{type: :assistant, data: %{message: %{"content" => []}}},
      make_tool_result_message(tool_name, content_text),
      %{type: :result, data: %{result: "done"}}
    ]
  end

  describe "extract_distillation/2" do
    test "successful extraction from valid tool_result" do
      payload = valid_payload()
      messages = make_messages_with_tool_result(@tool_name, tool_result_json(payload))

      assert {:ok, result} = ClaudeCode.extract_distillation(messages, "test-model")
      assert result.summary_json == payload
      assert result.model_used == "test-model"
      assert is_binary(result.summary_text)
      assert is_binary(result.raw_response_text)
      assert result.raw_response_text == Jason.encode!(payload)
    end

    test "missing tool result returns :no_distillation_tool_output" do
      messages = [
        %{type: :system, data: %{}},
        %{type: :result, data: %{result: "done"}}
      ]

      assert {:error, :no_distillation_tool_output} =
               ClaudeCode.extract_distillation(messages, "test-model")
    end

    test "wrong tool name is not matched" do
      messages = make_messages_with_tool_result("wrong_tool", tool_result_json(valid_payload()))

      assert {:error, :no_distillation_tool_output} =
               ClaudeCode.extract_distillation(messages, "test-model")
    end

    test "validation failure returns :invalid_distillation_payload" do
      error_json =
        Jason.encode!(%{"ok" => false, "error" => "validation_error", "details" => ["bad"]})

      messages = make_messages_with_tool_result(@tool_name, error_json)

      assert {:error, {:invalid_distillation_payload, "validation_failed", _}} =
               ClaudeCode.extract_distillation(messages, "test-model")
    end

    test "unexpected shape returns :invalid_distillation_payload" do
      weird_json = Jason.encode!(%{"ok" => true, "kind" => "unknown"})
      messages = make_messages_with_tool_result(@tool_name, weird_json)

      assert {:error, {:invalid_distillation_payload, "unexpected_shape", _}} =
               ClaudeCode.extract_distillation(messages, "test-model")
    end

    test "invalid JSON returns :invalid_distillation_payload" do
      messages = make_messages_with_tool_result(@tool_name, "not json{{{")

      assert {:error, {:invalid_distillation_payload, "json_decode_error", _}} =
               ClaudeCode.extract_distillation(messages, "test-model")
    end

    test "uses last tool result when multiple present" do
      first_payload = Map.put(valid_payload(), "session_summary", "First")
      second_payload = Map.put(valid_payload(), "session_summary", "Second")

      messages = [
        %{type: :system, data: %{}},
        make_tool_result_message(@tool_name, tool_result_json(first_payload)),
        make_tool_result_message(@tool_name, tool_result_json(second_payload)),
        %{type: :result, data: %{result: "done"}}
      ]

      assert {:ok, result} = ClaudeCode.extract_distillation(messages, "m")
      assert result.summary_json["session_summary"] == "Second"
    end
  end

  describe "format_summary_text/1" do
    test "includes session_summary" do
      text = ClaudeCode.format_summary_text(%{"session_summary" => "Did stuff"})
      assert text == "Did stuff"
    end

    test "formats all sections" do
      payload = %{
        "session_summary" => "Summary here",
        "what_changed" => ["A", "B"],
        "key_files" => [%{"path" => "lib/x.ex", "reason" => "Main"}],
        "open_threads" => ["Thread 1"],
        "risks" => ["Risk 1"]
      }

      text = ClaudeCode.format_summary_text(payload)
      assert text =~ "Summary here"
      assert text =~ "What changed:\n- A\n- B"
      assert text =~ "Key files:\n- lib/x.ex - Main"
      assert text =~ "Open threads:\n- Thread 1"
      assert text =~ "Risks:\n- Risk 1"
    end

    test "omits nil and empty arrays" do
      payload = %{
        "session_summary" => "Just summary",
        "what_changed" => [],
        "key_files" => nil,
        "open_threads" => nil,
        "risks" => []
      }

      text = ClaudeCode.format_summary_text(payload)
      assert text == "Just summary"
    end
  end

  describe "extract_last_tool_result/2" do
    test "extracts text from string content" do
      messages = [
        %{
          type: :tool_result,
          data: %{tool_name: "my_tool", content: "raw text"}
        }
      ]

      assert ClaudeCode.extract_last_tool_result(messages, "my_tool") == "raw text"
    end

    test "extracts text from content block list" do
      messages = [
        %{
          type: :tool_result,
          data: %{
            tool_name: "my_tool",
            content: [%{"type" => "text", "text" => "block text"}]
          }
        }
      ]

      assert ClaudeCode.extract_last_tool_result(messages, "my_tool") == "block text"
    end

    test "returns nil when no matching tool" do
      messages = [%{type: :assistant, data: %{}}]
      assert ClaudeCode.extract_last_tool_result(messages, "missing") == nil
    end
  end
end
