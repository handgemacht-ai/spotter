defmodule Spotter.Services.SessionDistiller.ClaudeCodeTest do
  use ExUnit.Case, async: true

  alias Spotter.Agents.DistillationTools
  alias Spotter.Observability.AgentRunScope
  alias Spotter.Services.SessionDistiller.ClaudeCode

  defp valid_payload do
    %{
      session_summary: "Implemented auth flow",
      what_changed: ["Added login endpoint"],
      commands_run: ["mix test"],
      open_threads: [],
      risks: ["No rate limiting"],
      key_files: [%{path: "lib/auth.ex", reason: "Core auth module"}],
      important_snippets: [
        %{
          relative_path: "lib/auth.ex",
          line_start: 10,
          line_end: 25,
          snippet: "def authenticate(user, pass)",
          why_important: "Main auth entry point"
        }
      ],
      distillation_metadata: %{
        confidence: 0.9,
        source_sections: ["transcript"]
      }
    }
  end

  describe "ETS result storage" do
    test "store_result and fetch_result round-trip via registry pid" do
      AgentRunScope.ensure_table_exists()
      # Simulate: runner stores scope, tool resolves via registry hint
      registry_pid = self()
      AgentRunScope.put(registry_pid, %{agent_kind: "session_distiller"})
      Process.put(:claude_agent_sdk_tool_registry_pid, registry_pid)

      payload = valid_payload()
      DistillationTools.store_result({:ok, :session, payload})

      result = DistillationTools.fetch_result(registry_pid)
      assert {:ok, :session, ^payload} = result

      # fetch_result deletes — second call returns nil
      assert DistillationTools.fetch_result(registry_pid) == nil
    after
      AgentRunScope.delete(self())
      Process.delete(:claude_agent_sdk_tool_registry_pid)
    end

    test "fetch_result returns nil when no result stored" do
      AgentRunScope.ensure_table_exists()
      assert DistillationTools.fetch_result(self()) == nil
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

  describe "enforce_tool_contract/1" do
    test "appends mandatory tool call contract with correct tool name" do
      prompt = "Custom user prompt about sessions."
      result = ClaudeCode.enforce_tool_contract(prompt)

      assert result =~ "Custom user prompt about sessions."
      assert result =~ "mcp__spotter-distill__record_session_distillation"
      assert result =~ "MANDATORY OUTPUT CONTRACT"
    end

    test "prohibits free-form JSON and markdown" do
      result = ClaudeCode.enforce_tool_contract("Any prompt.")

      assert result =~ "Do NOT return markdown"
      assert result =~ "Do NOT return free-form JSON outside of a tool call"
    end

    test "contract cannot be removed by DB/env override" do
      override_prompt = "Completely custom prompt without any tool mention."
      result = ClaudeCode.enforce_tool_contract(override_prompt)

      assert result =~ "Completely custom prompt"
      assert result =~ "mcp__spotter-distill__record_session_distillation"
      assert result =~ "MANDATORY OUTPUT CONTRACT"
    end
  end
end
