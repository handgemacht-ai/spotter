defmodule Spotter.Services.ProjectRollupDistiller.ClaudeCode do
  @moduledoc "Claude Code adapter for project rollup distillation via `claude_agent_sdk`."
  @behaviour Spotter.Services.ProjectRollupDistiller

  require OpenTelemetry.Tracer, as: Tracer

  alias Spotter.Observability.ErrorReport
  alias Spotter.Services.ClaudeCode.Client
  alias Spotter.Services.ClaudeCode.ResultExtractor

  @default_model "claude-3-5-haiku-latest"
  @default_timeout 15_000

  @system_prompt """
  You are summarizing a project's activity over a time period for a developer activity log.
  Given session summaries and commit information, produce a JSON summary of the period.

  Keep each field concise. Omit empty arrays. Focus on committed work.
  """

  @json_schema %{
    "type" => "object",
    "required" => ["period_summary"],
    "properties" => %{
      "period_summary" => %{"type" => "string"},
      "themes" => %{"type" => "array", "items" => %{"type" => "string"}},
      "open_threads" => %{"type" => "array", "items" => %{"type" => "string"}},
      "risks" => %{"type" => "array", "items" => %{"type" => "string"}},
      "notable_commits" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "required" => ["hash", "why_it_matters"],
          "properties" => %{
            "hash" => %{"type" => "string"},
            "why_it_matters" => %{"type" => "string"}
          }
        }
      }
    }
  }

  @impl true
  def distill(pack, opts \\ []) do
    model = Keyword.get(opts, :model, configured_model())
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    Tracer.with_span "spotter.project_rollup_distiller.distill" do
      Tracer.set_attribute("spotter.model_requested", model)

      case Client.query_json_schema(@system_prompt, format_pack(pack), @json_schema,
             model: model,
             timeout_ms: timeout
           ) do
        {:ok, %{output: json, model_used: model_used, messages: messages}} ->
          actual_model = model_used || ResultExtractor.extract_model_used(messages) || model
          Tracer.set_attribute("spotter.model_used", actual_model)

          if Map.has_key?(json, "period_summary") do
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
          ErrorReport.set_trace_error(
            "distill_error",
            inspect(reason),
            "services.project_rollup_distiller"
          )

          {:error, reason}
      end
    end
  end

  defp format_summary_text(json) do
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

  defp configured_model do
    System.get_env("SPOTTER_PROJECT_ROLLUP_MODEL") || @default_model
  end
end
