defmodule Mix.Tasks.Spotter.Transcripts.Errors do
  @moduledoc "Focused error analysis for tool call runs."
  @shortdoc "Analyze tool call errors"
  use Mix.Task

  alias Spotter.Services.TranscriptAnalytics

  @switches [
    project: :string,
    session: :string,
    since: :string,
    tool: :string,
    top: :integer,
    classify: :boolean,
    format: :string
  ]

  @impl true
  def run(args) do
    if "--help" in args do
      print_usage()
    else
      do_run(args)
    end
  end

  defp do_run(args) do
    Mix.Tasks.Spotter.CliHelpers.start_app_without_server()

    opts = Mix.Tasks.Spotter.CliHelpers.parse_args!(args, @switches, &print_usage/0)

    errors =
      TranscriptAnalytics.error_analysis(%{
        project_id: opts[:project],
        session_id: opts[:session],
        since: opts[:since],
        tool: opts[:tool],
        top: opts[:top],
        classify: opts[:classify] || false
      })

    format = opts[:format] || "table"
    classify? = opts[:classify] || false
    print_result(errors, format, classify?)
  end

  defp print_result(errors, "json", _classify?) do
    Mix.shell().info(Jason.encode!(errors, pretty: true))
  end

  defp print_result([], _table, _classify?) do
    Mix.shell().info("No errors found.")
  end

  defp print_result(errors, _table, classify?) do
    Mix.shell().info("Error Analysis (#{length(errors)} patterns):\n")

    Enum.each(errors, fn e ->
      Mix.shell().info("  #{e.tool_name} — #{e.count} occurrences")
      Mix.shell().info("    Fingerprint: #{e.fingerprint}")

      if classify? do
        Mix.shell().info("    Category:    #{e.category} (#{e.preventability})")
        Mix.shell().info("    Error rate:  #{e.error_rate}% of #{e.total_tool_calls} total calls")
      end

      Mix.shell().info("    First seen:  #{format_dt(e.first_seen)}")
      Mix.shell().info("    Last seen:   #{format_dt(e.last_seen)}")
      Mix.shell().info("    Sample:      #{String.slice(e.sample_error, 0, 120)}")
      Mix.shell().info("")
    end)
  end

  defp format_dt(nil), do: "unknown"
  defp format_dt(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp print_usage do
    Mix.shell().info("""
    Usage: mix spotter.transcripts.errors [options]

    Analyze tool call errors with fingerprinting.

    Options:
      --project <id>        Filter by project ID
      --session <id>        Filter by session ID
      --since <YYYY-MM-DD>  Only errors after this date
      --tool <name>         Filter by tool name
      --top <n>             Max error patterns (default: 20)
      --classify            Add category, preventability, and error rate
      --format <fmt>        table (default) or json
    """)
  end
end
