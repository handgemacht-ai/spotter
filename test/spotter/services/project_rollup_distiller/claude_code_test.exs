defmodule Spotter.Services.ProjectRollupDistiller.ClaudeCodeTest do
  use ExUnit.Case, async: true

  alias Spotter.Agents.DistillationTools
  alias Spotter.Observability.AgentRunScope
  alias Spotter.Services.ProjectRollupDistiller.ClaudeCode

  describe "ETS result storage for rollup" do
    test "store_result and fetch_result round-trip" do
      AgentRunScope.ensure_table_exists()
      registry_pid = self()
      AgentRunScope.put(registry_pid, %{agent_kind: "project_rollup_distiller"})
      Process.put(:claude_agent_sdk_tool_registry_pid, registry_pid)

      payload = %{
        period_summary: "Productive week",
        themes: ["Auth"],
        notable_commits: [],
        open_threads: [],
        risks: [],
        important_snippets: [],
        distillation_metadata: %{confidence: 0.85, source_sections: ["sessions"]}
      }

      DistillationTools.store_result({:ok, :project_rollup, payload})

      result = DistillationTools.fetch_result(registry_pid)
      assert {:ok, :project_rollup, ^payload} = result
      assert DistillationTools.fetch_result(registry_pid) == nil
    after
      AgentRunScope.delete(self())
      Process.delete(:claude_agent_sdk_tool_registry_pid)
    end
  end

  describe "enforce_tool_contract/1" do
    @tool_name "mcp__spotter-distill__record_project_rollup_distillation"

    test "appends mandatory tool call contract with correct tool name" do
      prompt = "Custom rollup prompt."
      result = ClaudeCode.enforce_tool_contract(prompt)

      assert result =~ "Custom rollup prompt."
      assert result =~ @tool_name
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
      assert result =~ @tool_name
      assert result =~ "MANDATORY OUTPUT CONTRACT"
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
