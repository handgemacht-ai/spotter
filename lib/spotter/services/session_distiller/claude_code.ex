defmodule Spotter.Services.SessionDistiller.ClaudeCode do
  @moduledoc "Claude Code adapter for session distillation via `claude_agent_sdk`."
  @behaviour Spotter.Services.SessionDistiller

  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Services.ClaudeCode.Client
  alias Spotter.Services.ClaudeCode.ResultExtractor

  @default_model "claude-3-5-haiku-latest"
  @default_timeout 15_000

  @system_prompt """
  You are summarizing a completed Claude Code session for a developer activity log.
  Given session metadata, tool calls, file snapshots, errors, commits, and a transcript slice, produce a JSON summary.

  Keep each field concise. Omit empty arrays.
  Focus on session activity (tool calls, file snapshots, errors, transcript slice).
  Use commit information only as supporting context.
  """

  @json_schema %{
    "type" => "object",
    "required" => ["session_summary"],
    "properties" => %{
      "session_summary" => %{"type" => "string"},
      "what_changed" => %{"type" => "array", "items" => %{"type" => "string"}},
      "commands_run" => %{"type" => "array", "items" => %{"type" => "string"}},
      "open_threads" => %{"type" => "array", "items" => %{"type" => "string"}},
      "risks" => %{"type" => "array", "items" => %{"type" => "string"}},
      "key_files" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "required" => ["path"],
          "properties" => %{
            "path" => %{"type" => "string"},
            "reason" => %{"type" => "string"}
          }
        }
      }
    }
  }

  @impl true
  def distill(pack, opts \\ []) do
    model = Keyword.get(opts, :model, configured_model())
    timeout = Keyword.get(opts, :timeout, configured_timeout())

    Tracer.with_span "spotter.session_distiller.distill" do
      Tracer.set_attribute("spotter.model_requested", model)

      case Client.query_json_schema(@system_prompt, format_pack(pack), @json_schema,
             model: model,
             timeout_ms: timeout
           ) do
        {:ok, %{output: json, model_used: model_used, messages: messages}} ->
          actual_model = model_used || ResultExtractor.extract_model_used(messages) || model
          Tracer.set_attribute("spotter.model_used", actual_model)

          if Map.has_key?(json, "session_summary") do
            raw_text = Jason.encode!(json)

            {:ok,
             %{
               summary_json: json,
               summary_text: format_summary_text(json),
               model_used: actual_model,
               raw_response_text: raw_text
             }}
          else
            {:error, {:invalid_json, :missing_required_keys, Jason.encode!(json)}}
          end

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          {:error, reason}
      end
    end
  end

  defp format_summary_text(json) do
    sections = [
      json["session_summary"],
      format_list("What changed", json["what_changed"]),
      format_key_files(json["key_files"]),
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

  defp format_key_files(nil), do: nil
  defp format_key_files([]), do: nil

  defp format_key_files(files) do
    bullets =
      Enum.map_join(files, "\n", fn
        %{"path" => p, "reason" => r} -> "- #{p} - #{r}"
        %{"path" => p} -> "- #{p}"
        other -> "- #{inspect(other)}"
      end)

    "Key files:\n#{bullets}"
  end

  defp format_pack(pack) do
    sections = [
      "## Session",
      Jason.encode!(pack.session, pretty: true),
      "## Tool calls",
      Jason.encode!(pack.tool_calls, pretty: true),
      "## File snapshots",
      Jason.encode!(pack.file_snapshots, pretty: true),
      "## Errors",
      Jason.encode!(pack.errors, pretty: true),
      "## Commits (#{length(pack.commits)})",
      Jason.encode!(pack.commits, pretty: true),
      "## Stats",
      Jason.encode!(pack.stats, pretty: true),
      "## Transcript Slice",
      pack.transcript_slice
    ]

    Enum.join(sections, "\n\n")
  end

  defp configured_model do
    System.get_env("SPOTTER_SESSION_DISTILL_MODEL") || @default_model
  end

  defp configured_timeout do
    case System.get_env("SPOTTER_DISTILL_TIMEOUT_MS") do
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
