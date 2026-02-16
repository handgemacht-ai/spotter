defmodule Spotter.Agents.HotspotTools do
  @moduledoc """
  In-process MCP tools for commit hotspot analysis.

  Provides a read-only tool for fetching file content at a specific commit,
  with optional line-range slicing to minimize payload size.
  """

  use ClaudeAgentSDK.Tool

  alias Spotter.Observability.ErrorReport

  deftool :repo_read_file_at_commit,
          "Read a repo file at a specific commit (optionally sliced by line range)",
          %{
            type: "object",
            properties: %{
              commit_hash: %{type: "string", description: "Git commit hash"},
              relative_path: %{type: "string", description: "Repo-relative file path"},
              line_start: %{type: "integer", description: "Start line (1-based) for slicing"},
              line_end: %{type: "integer", description: "End line (1-based) for slicing"},
              context_before: %{
                type: "integer",
                description: "Extra lines before line_start (default 20)"
              },
              context_after: %{
                type: "integer",
                description: "Extra lines after line_end (default 20)"
              },
              max_chars: %{
                type: "integer",
                description: "Maximum characters to return (default 60000)"
              }
            },
            required: ["commit_hash", "relative_path"]
          },
          annotations: %{readOnlyHint: true} do
    require OpenTelemetry.Tracer, as: Tracer

    alias Spotter.Agents.HotspotTools.Helpers
    alias Spotter.Services.GitRunner

    def execute(%{"commit_hash" => hash, "relative_path" => path} = input) do
      max_chars = input["max_chars"] || 60_000
      cwd = Helpers.git_cwd()

      Tracer.with_span "spotter.commit_hotspots.tool.repo_read_file_at_commit" do
        Tracer.set_attribute("spotter.commit_hash", hash)
        Tracer.set_attribute("spotter.relative_path", path)
        Tracer.set_attribute("spotter.max_chars", max_chars)

        case read_file(cwd, hash, path) do
          {:ok, content} ->
            build_response(content, hash, path, input, max_chars)

          {:error, reason} ->
            ErrorReport.set_trace_error("git_show_error", reason, "agents.hotspot_tools")

            Helpers.text_result(%{
              ok: false,
              commit_hash: hash,
              relative_path: path,
              error: reason
            })
        end
      end
    end

    defp read_file(nil, _hash, _path), do: {:error, "git_cwd not available"}

    defp read_file(cwd, hash, path) do
      case GitRunner.run(["show", "#{hash}:#{path}"],
             cd: cwd,
             timeout_ms: 10_000,
             max_bytes: 1_500_000
           ) do
        {:ok, output} -> {:ok, output}
        {:error, err} -> {:error, err[:output] || inspect(err.kind)}
      end
    end

    defp build_response(content, hash, path, input, max_chars) do
      all_lines = String.split(content, "\n")
      total_lines = length(all_lines)

      case input["line_start"] do
        nil ->
          truncated = byte_size(content) > max_chars
          content = if truncated, do: String.slice(content, 0, max_chars), else: content

          Helpers.text_result(%{
            ok: true,
            commit_hash: hash,
            relative_path: path,
            content: content,
            bytes: byte_size(content),
            truncated: truncated
          })

        line_start ->
          line_end = input["line_end"] || line_start
          ctx_before = input["context_before"] || 20
          ctx_after = input["context_after"] || 20

          slice_start = max(line_start - ctx_before, 1)
          slice_end = min(line_end + ctx_after, total_lines)

          sliced =
            all_lines
            |> Enum.slice((slice_start - 1)..(slice_end - 1)//1)
            |> Enum.join("\n")

          truncated = byte_size(sliced) > max_chars
          sliced = if truncated, do: String.slice(sliced, 0, max_chars), else: sliced

          Helpers.text_result(%{
            ok: true,
            commit_hash: hash,
            relative_path: path,
            content: sliced,
            bytes: byte_size(sliced),
            truncated: truncated,
            slice: %{
              line_start: slice_start,
              line_end: slice_end,
              total_lines: total_lines
            }
          })
      end
    end
  end

  @doc "Returns all tool modules for MCP server registration."
  def all_tool_modules do
    __MODULE__
    |> ClaudeAgentSDK.Tool.list_tools()
    |> Enum.map(& &1.module)
  end

  defmodule Helpers do
    @moduledoc false

    alias Spotter.Observability.AgentRunScope

    def set_git_cwd(cwd) do
      Process.put(:hotspot_agent_git_cwd, cwd)
      :ok
    end

    def git_cwd do
      case AgentRunScope.resolve_for_current_process() do
        {:ok, %{git_cwd: cwd}} when is_binary(cwd) -> cwd
        _ -> Process.get(:hotspot_agent_git_cwd)
      end
    end

    def text_result(data) do
      {:ok, %{"content" => [%{"type" => "text", "text" => Jason.encode!(data)}]}}
    end
  end
end
