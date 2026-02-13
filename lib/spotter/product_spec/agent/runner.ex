defmodule Spotter.ProductSpec.Agent.Runner do
  @moduledoc """
  Runs the product specification agent in-process using the Claude Agent SDK.

  Replaces the previous TypeScript subprocess approach with a direct Elixir
  implementation that uses the same Dolt Ecto repo already running in the
  application.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Config.Runtime
  alias Spotter.ProductSpec.Agent.Prompt
  alias Spotter.ProductSpec.Agent.ToolHelpers
  alias Spotter.ProductSpec.Agent.Tools

  @max_turns 15

  @tool_names ~w(
    domains_list domains_create domains_update
    features_search features_create features_update features_delete
    requirements_search requirements_create requirements_update requirements_delete
    requirements_add_evidence_files
    repo_read_file_at_commit repo_list_files_at_commit
  )

  @doc """
  Runs the spec agent for the given input map.

  Sets the commit hash for write tracking, creates an in-process MCP server,
  and invokes `ClaudeAgentSDK.query/2` with the system prompt.

  Returns `{:ok, output}` on success or `{:error, reason}` on failure.
  """
  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(input) do
    Tracer.with_span "spotter.product_spec.invoke_agent" do
      ToolHelpers.set_commit_hash(input.commit_hash)
      ToolHelpers.set_git_cwd(Map.get(input, :git_cwd))

      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "spec-tools",
          version: "1.0.0",
          tools: Tools.all_tool_modules()
        )

      allowed_tools = Enum.map(@tool_names, &"mcp__spec-tools__#{&1}")
      {system_prompt_template, _source} = Runtime.product_spec_system_prompt()
      system_prompt = Prompt.build_system_prompt(input, system_prompt_template)

      opts = %ClaudeAgentSDK.Options{
        mcp_servers: %{"spec-tools" => server},
        allowed_tools: allowed_tools,
        max_turns: @max_turns
      }

      tool_calls = []
      changed_count = 0

      try do
        {tool_calls, changed_count} =
          system_prompt
          |> ClaudeAgentSDK.query(opts)
          |> Enum.reduce({tool_calls, changed_count}, &collect_tool_calls/2)

        output = %{
          ok: true,
          tool_calls: tool_calls,
          changed_entities_count: changed_count
        }

        {:ok, output}
      rescue
        e ->
          reason = Exception.message(e)
          Logger.warning("SpecAgent: failed: #{reason}")
          Tracer.set_status(:error, reason)
          {:error, reason}
      end
    end
  end

  defp collect_tool_calls(message, {tool_calls, changed_count}) do
    case message do
      %{type: "assistant", message: %{content: content}} when is_list(content) ->
        Enum.reduce(content, {tool_calls, changed_count}, fn
          %{type: "tool_use", name: name}, {tc, cc} ->
            is_write =
              String.contains?(name, "create") or
                String.contains?(name, "update") or
                String.contains?(name, "delete")

            {tc ++ [%{name: name, ms: 0}], if(is_write, do: cc + 1, else: cc)}

          _, acc ->
            acc
        end)

      _ ->
        {tool_calls, changed_count}
    end
  end
end
