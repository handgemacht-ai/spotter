defmodule Spotter.Services.ProjectRollupDistiller.ClaudeCode do
  @moduledoc "Claude Code adapter for project rollup distillation via in-process MCP tool-loop."
  @behaviour Spotter.Services.ProjectRollupDistiller

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Agents.DistillationToolServer
  alias Spotter.Config.Runtime
  alias Spotter.Observability.AgentRunScope
  alias Spotter.Observability.ClaudeAgentFlow
  alias Spotter.Observability.ErrorReport
  alias Spotter.Observability.FlowKeys
  alias Spotter.Services.ClaudeCode.ResultExtractor

  @default_model "claude-3-5-haiku-latest"
  @default_timeout 45_000
  @max_turns 6

  @tool_name "mcp__spotter-distill__record_project_rollup_distillation"

  @tool_contract_suffix """

  ## MANDATORY OUTPUT CONTRACT

  You MUST deliver your final output by calling the MCP tool `#{@tool_name}`.
  Do NOT return markdown. Do NOT return free-form JSON outside of a tool call.
  Your response must contain exactly one call to `#{@tool_name}` with the complete distillation payload.
  """

  @impl true
  def distill(pack, opts \\ []) do
    model = Keyword.get(opts, :model, configured_model())
    timeout = Keyword.get(opts, :timeout, configured_timeout())
    {system_prompt, _source} = Runtime.project_rollup_system_prompt()
    system_prompt = enforce_tool_contract(system_prompt)

    Tracer.with_span "spotter.project_rollup_distiller.distill" do
      Tracer.set_attribute("spotter.model_requested", model)
      Tracer.set_attribute("spotter.timeout_ms", timeout)

      server = DistillationToolServer.create_server()

      AgentRunScope.put(server.registry_pid, %{
        agent_kind: "project_rollup_distiller"
      })

      try do
        run_agent(pack, server, system_prompt, model, timeout)
      rescue
        e ->
          reason = Exception.message(e)
          Logger.warning("ProjectRollupDistiller: agent failed: #{reason}")

          ErrorReport.set_trace_error(
            "distill_error",
            reason,
            "services.project_rollup_distiller"
          )

          {:error, {:agent_error, reason}}
      catch
        :exit, exit_reason ->
          msg = "ProjectRollupDistiller: SDK process exited: #{inspect(exit_reason)}"
          Logger.warning(msg)

          ErrorReport.set_trace_error(
            "distill_exit",
            msg,
            "services.project_rollup_distiller"
          )

          {:error, {:agent_exit, exit_reason}}
      after
        AgentRunScope.delete(server.registry_pid)
      end
    end
  end

  defp run_agent(pack, server, system_prompt, model, timeout) do
    sdk_opts =
      %ClaudeAgentSDK.Options{
        model: model,
        system_prompt: system_prompt,
        max_turns: @max_turns,
        timeout_ms: timeout,
        tools: [],
        allowed_tools: DistillationToolServer.allowed_project_rollup_tools(),
        permission_mode: :dont_ask,
        mcp_servers: %{"spotter-distill" => server}
      }
      |> ClaudeAgentFlow.build_opts()

    project_id = to_string(pack.project.id)
    flow_keys = [FlowKeys.project(project_id)]

    messages =
      format_pack(pack)
      |> ClaudeAgentSDK.query(sdk_opts)
      |> ClaudeAgentFlow.wrap_stream(flow_keys: flow_keys)
      |> Enum.to_list()

    actual_model = ResultExtractor.extract_model_used(messages) || model
    Tracer.set_attribute("spotter.model_used", actual_model)
    Tracer.set_attribute("spotter.tool_calls_total", count_tool_calls(messages))

    extract_distillation(messages, actual_model)
  end

  @doc false
  def extract_distillation(messages, model_used) do
    case extract_last_tool_result(messages, @tool_name) do
      nil ->
        log_missing_tool_diagnostics(messages, @tool_name, model_used)
        {:error, :no_distillation_tool_output}

      raw_json ->
        case Jason.decode(raw_json) do
          {:ok, %{"ok" => true, "kind" => "project_rollup", "payload" => payload}} ->
            snippet_count = length(Map.get(payload, "important_snippets", []))
            Tracer.set_attribute("spotter.snippets_count", snippet_count)

            summary_json = payload
            summary_text = format_summary_text(payload)
            raw_text = Jason.encode!(summary_json)

            {:ok,
             %{
               summary_json: summary_json,
               summary_text: summary_text,
               model_used: model_used,
               raw_response_text: raw_text
             }}

          {:ok, %{"ok" => false} = err} ->
            {:error, {:invalid_distillation_payload, "validation_failed", Jason.encode!(err)}}

          {:ok, other} ->
            {:error, {:invalid_distillation_payload, "unexpected_shape", Jason.encode!(other)}}

          {:error, decode_err} ->
            {:error, {:invalid_distillation_payload, "json_decode_error", inspect(decode_err)}}
        end
    end
  end

  @doc false
  def extract_last_tool_result(messages, tool_name) do
    messages
    |> Enum.flat_map(&extract_tool_results/1)
    |> Enum.filter(fn {name, _content} -> name == tool_name end)
    |> List.last()
    |> case do
      {_name, content} -> content
      nil -> nil
    end
  end

  defp extract_tool_results(%ClaudeAgentSDK.Message{type: :tool_result, data: data}) do
    extract_tool_result_pairs(data)
  end

  defp extract_tool_results(%{type: :tool_result, data: data}) do
    extract_tool_result_pairs(data)
  end

  defp extract_tool_results(_), do: []

  defp extract_tool_result_pairs(data) when is_map(data) do
    tool_name = data[:tool_name] || data["tool_name"]
    content = data[:content] || data["content"]

    if tool_name && content do
      [{tool_name, extract_text_content(content)}]
    else
      []
    end
  end

  defp extract_tool_result_pairs(_), do: []

  defp extract_text_content(content) when is_binary(content), do: content

  defp extract_text_content(content) when is_list(content) do
    Enum.find_value(content, "", fn
      %{"type" => "text", "text" => text} -> text
      %{type: "text", text: text} -> text
      _ -> nil
    end)
  end

  defp extract_text_content(_), do: ""

  @doc false
  def format_summary_text(json) do
    sections = [
      json["period_summary"],
      format_list("Themes", json["themes"]),
      format_list("Open threads", json["open_threads"]),
      format_list("Risks", json["risks"])
    ]

    sections |> Enum.reject(&is_nil/1) |> Enum.join("\n\n")
  end

  defp format_list(_heading, nil), do: nil
  defp format_list(_heading, []), do: nil

  defp format_list(heading, items) do
    bullets = Enum.map_join(items, "\n", &("- " <> to_string(&1)))
    "#{heading}:\n#{bullets}"
  end

  defp format_pack(pack) do
    sections = [
      "## Project: #{pack.project.name}",
      "Period: #{pack.bucket.bucket_kind} starting #{pack.bucket.bucket_start_date}",
      "## Sessions (#{length(pack.sessions)})",
      Jason.encode!(pack.sessions, pretty: true)
    ]

    Enum.join(sections, "\n\n")
  end

  defp count_tool_calls(messages) do
    messages
    |> Enum.flat_map(&extract_assistant_tool_uses/1)
    |> length()
  end

  defp extract_assistant_tool_uses(%ClaudeAgentSDK.Message{
         type: :assistant,
         data: %{message: %{"content" => content}}
       })
       when is_list(content) do
    for %{"type" => "tool_use"} <- content, do: :call
  end

  defp extract_assistant_tool_uses(%ClaudeAgentSDK.Message{
         type: :assistant,
         data: %{message: %{content: content}}
       })
       when is_list(content) do
    for %{"type" => "tool_use"} <- content, do: :call
  end

  defp extract_assistant_tool_uses(_), do: []

  defp log_missing_tool_diagnostics(messages, expected_tool, model_used) do
    tool_results = Enum.flat_map(messages, &extract_tool_results/1)
    tool_use_count = count_tool_calls(messages)
    observed_names = tool_results |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    diag = %{
      expected_tool: expected_tool,
      model_used: model_used,
      assistant_tool_use_count: tool_use_count,
      tool_result_count: length(tool_results),
      observed_tool_names: observed_names
    }

    Logger.warning("ProjectRollupDistiller: no_distillation_tool_output — #{inspect(diag)}")

    Tracer.set_attribute("spotter.distill.expected_tool", expected_tool)
    Tracer.set_attribute("spotter.distill.tool_use_count", tool_use_count)
    Tracer.set_attribute("spotter.distill.tool_result_count", length(tool_results))
    Tracer.set_attribute("spotter.distill.observed_tools", Enum.join(observed_names, ","))
    Tracer.set_status(:error, "no_distillation_tool_output")
  end

  @doc false
  def enforce_tool_contract(prompt) do
    String.trim_trailing(prompt) <> @tool_contract_suffix
  end

  defp configured_model do
    System.get_env("SPOTTER_PROJECT_ROLLUP_MODEL") || @default_model
  end

  defp configured_timeout do
    case System.get_env("SPOTTER_PROJECT_ROLLUP_DISTILL_TIMEOUT_MS") do
      nil -> @default_timeout
      "" -> @default_timeout
      val -> parse_int(val, @default_timeout)
    end
  end

  defp parse_int(val, fallback) do
    case Integer.parse(String.trim(val)) do
      {int, ""} when int > 0 -> int
      _ -> fallback
    end
  end
end
