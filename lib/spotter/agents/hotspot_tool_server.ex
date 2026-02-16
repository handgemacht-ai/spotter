defmodule Spotter.Agents.HotspotToolServer do
  @moduledoc """
  Creates the in-process SDK MCP server for commit hotspot analysis tools.
  """

  alias Spotter.Agents.HotspotTools

  @server_name "spotter-hotspots"

  @tool_names [
    "mcp__spotter-hotspots__repo_read_file_at_commit"
  ]

  @doc "Creates an SDK MCP server with hotspot tools registered."
  def create_server do
    ClaudeAgentSDK.create_sdk_mcp_server(
      name: @server_name,
      version: "1.0.0",
      tools: HotspotTools.all_tool_modules()
    )
  end

  @doc "Returns the allowlisted tool names for agent configuration."
  def allowed_tools, do: @tool_names
end
