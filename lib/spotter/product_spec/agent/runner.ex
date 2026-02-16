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
  alias Spotter.Observability.AgentRunScope
  alias Spotter.Observability.ClaudeAgentFlow
  alias Spotter.Observability.ErrorReport
  alias Spotter.Observability.FlowKeys
  alias Spotter.ProductSpec.Agent.Prompt
  alias Spotter.ProductSpec.Agent.ToolHelpers
  alias Spotter.ProductSpec.Agent.Tools
  alias Spotter.Services.ClaudeCode.ResultExtractor

  @max_turns 15
  @timeout_ms 300_000

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
      ToolHelpers.set_project_id(to_string(input.project_id))
      ToolHelpers.set_commit_hash(input.commit_hash)
      ToolHelpers.set_git_cwd(Map.get(input, :git_cwd))

      server =
        ClaudeAgentSDK.create_sdk_mcp_server(
          name: "spec-tools",
          version: "1.0.0",
          tools: Tools.all_tool_modules()
        )

      AgentRunScope.put(server.registry_pid, %{
        project_id: to_string(input.project_id),
        commit_hash: input.commit_hash,
        git_cwd: Map.get(input, :git_cwd),
        run_id: Map.get(input, :run_id),
        agent_kind: "product_spec"
      })

      allowed_tools = Enum.map(@tool_names, &"mcp__spec-tools__#{&1}")
      {system_prompt_template, _source} = Runtime.product_spec_system_prompt()
      system_prompt = Prompt.build_system_prompt(input, system_prompt_template)

      base_opts = %ClaudeAgentSDK.Options{
        mcp_servers: %{"spec-tools" => server},
        allowed_tools: allowed_tools,
        max_turns: @max_turns,
        timeout_ms: @timeout_ms,
        permission_mode: :dont_ask,
        tools: []
      }

      opts = ClaudeAgentFlow.build_opts(base_opts)

      flow_keys =
        [FlowKeys.project(to_string(input[:project_id] || "unknown"))] ++
          if(input[:commit_hash], do: [FlowKeys.commit(input.commit_hash)], else: [])

      tool_calls = []
      changed_count = 0

      try do
        messages =
          system_prompt
          |> ClaudeAgentSDK.query(opts)
          |> ClaudeAgentFlow.wrap_stream(flow_keys: flow_keys)
          |> Enum.to_list()

        {tool_calls, changed_count} =
          Enum.reduce(messages, {tool_calls, changed_count}, &collect_tool_calls/2)

        model_used = ResultExtractor.extract_model_used(messages)
        Tracer.set_attribute("spotter.model_used", model_used || "unknown")

        output = %{
          ok: true,
          tool_calls: tool_calls,
          changed_entities_count: changed_count,
          model_used: model_used
        }

        {:ok, output}
      rescue
        e ->
          reason = Exception.message(e)
          Logger.warning("SpecAgent: failed: #{reason}")
          Tracer.set_attribute("spotter.error.kind", "exception")
          Tracer.set_attribute("spotter.error.reason", String.slice(reason, 0, 500))
          ErrorReport.set_trace_error("agent_error", reason, "product_spec.agent.runner")
          {:error, reason}
      catch
        :exit, exit_reason ->
          msg = "SpecAgent: SDK process exited: #{inspect(exit_reason)}"
          Logger.warning(msg)
          Tracer.set_attribute("spotter.error.kind", "exit")
          Tracer.set_attribute("spotter.error.reason", String.slice(msg, 0, 500))
          ErrorReport.set_trace_error("agent_exit", msg, "product_spec.agent.runner")
          {:error, {:agent_exit, exit_reason}}
      after
        AgentRunScope.delete(server.registry_pid)
        ToolHelpers.set_project_id(nil)
        ToolHelpers.set_commit_hash("")
        ToolHelpers.set_git_cwd(nil)
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
