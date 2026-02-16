defmodule Spotter.Agents.DistillationToolServer do
  @moduledoc """
  Creates the in-process SDK MCP server for distillation tools.
  """

  alias Spotter.Agents.DistillationTools

  @server_name "spotter-distill"

  @session_tools [
    "mcp__spotter-distill__record_session_distillation"
  ]

  @project_rollup_tools [
    "mcp__spotter-distill__record_project_rollup_distillation"
  ]

  @doc "Creates an SDK MCP server with distillation tools registered."
  def create_server do
    ClaudeAgentSDK.create_sdk_mcp_server(
      name: @server_name,
      version: "1.0.0",
      tools: DistillationTools.all_tool_modules()
    )
  end

  @doc "Returns the allowlisted tool names for session distillation."
  def allowed_session_tools, do: @session_tools

  @doc "Returns the allowlisted tool names for project rollup distillation."
  def allowed_project_rollup_tools, do: @project_rollup_tools
end
