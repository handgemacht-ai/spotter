defmodule Spotter.Agents.TestToolServer do
  @moduledoc """
  Creates the in-process SDK MCP server for test case tools.
  """

  alias Spotter.Agents.TestTools

  @server_name "spotter-tests"

  @tool_names [
    "mcp__spotter-tests__list_tests",
    "mcp__spotter-tests__create_test",
    "mcp__spotter-tests__update_test",
    "mcp__spotter-tests__delete_test",
    "mcp__spotter-tests__list_spec_requirements",
    "mcp__spotter-tests__upsert_spec_test_links"
  ]

  @doc "Creates an SDK MCP server with all test tools registered."
  def create_server do
    ClaudeAgentSDK.create_sdk_mcp_server(
      name: @server_name,
      version: "1.0.0",
      tools: TestTools.all_tool_modules()
    )
  end

  @doc "Returns the allowlisted tool names for agent configuration."
  def allowed_tools, do: @tool_names
end
