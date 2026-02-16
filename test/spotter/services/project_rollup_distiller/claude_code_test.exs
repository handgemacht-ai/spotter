defmodule Spotter.Services.ProjectRollupDistiller.ClaudeCodeTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.ProjectRollupDistiller.ClaudeCode

  @tool_name "mcp__spotter-distill__record_project_rollup_distillation"

  defp valid_payload do
    %{
      "period_summary" => "Productive week on auth system",
      "themes" => ["Authentication", "Testing"],
      "notable_commits" => [%{"hash" => "abc123", "why_it_matters" => "Added OAuth"}],
      "open_threads" => ["Token refresh edge case"],
      "risks" => ["Rate limiting not implemented"],
      "important_snippets" => [],
      "distillation_metadata" => %{
        "confidence" => 0.85,
        "source_sections" => ["sessions"]
      }
    }
  end

  defp tool_result_json(payload) do
    Jason.encode!(%{"ok" => true, "kind" => "project_rollup", "payload" => payload})
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

    test "wrong kind returns :invalid_distillation_payload" do
      # Using session kind instead of project_rollup
      session_json =
        Jason.encode!(%{"ok" => true, "kind" => "session", "payload" => valid_payload()})

      messages = make_messages_with_tool_result(@tool_name, session_json)

      assert {:error, {:invalid_distillation_payload, "unexpected_shape", _}} =
               ClaudeCode.extract_distillation(messages, "test-model")
    end

    test "validation failure returns :invalid_distillation_payload" do
      error_json =
        Jason.encode!(%{"ok" => false, "error" => "validation_error", "details" => ["bad"]})

      messages = make_messages_with_tool_result(@tool_name, error_json)

      assert {:error, {:invalid_distillation_payload, "validation_failed", _}} =
               ClaudeCode.extract_distillation(messages, "test-model")
    end

    test "invalid JSON returns :invalid_distillation_payload" do
      messages = make_messages_with_tool_result(@tool_name, "not json{{{")

      assert {:error, {:invalid_distillation_payload, "json_decode_error", _}} =
               ClaudeCode.extract_distillation(messages, "test-model")
    end
  end

  describe "format_summary_text/1" do
    test "includes period_summary" do
      text = ClaudeCode.format_summary_text(%{"period_summary" => "Good week"})
      assert text == "Good week"
    end

    test "formats all sections" do
      payload = %{
        "period_summary" => "Summary here",
        "themes" => ["Auth", "Testing"],
        "open_threads" => ["Thread 1"],
        "risks" => ["Risk 1"]
      }

      text = ClaudeCode.format_summary_text(payload)
      assert text =~ "Summary here"
      assert text =~ "Themes:\n- Auth\n- Testing"
      assert text =~ "Open threads:\n- Thread 1"
      assert text =~ "Risks:\n- Risk 1"
    end

    test "omits nil and empty arrays" do
      payload = %{
        "period_summary" => "Just summary",
        "themes" => [],
        "open_threads" => nil,
        "risks" => []
      }

      text = ClaudeCode.format_summary_text(payload)
      assert text == "Just summary"
    end
  end
end
