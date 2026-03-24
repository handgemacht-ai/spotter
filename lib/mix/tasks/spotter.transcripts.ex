defmodule Mix.Tasks.Spotter.Transcripts do
  @moduledoc "List available transcript analytics commands."
  @shortdoc "Transcript analytics CLI"
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.shell().info("""
    Spotter Transcript Analytics CLI

    Commands:

      mix spotter.transcripts.sync           Import/re-import transcripts and derive tool call runs
      mix spotter.transcripts.search         Search tool call runs across sessions with filters
      mix spotter.transcripts.inspect        Inspect tool call runs for a specific session
      mix spotter.transcripts.compare        Compare tool runs between two session cohorts
      mix spotter.transcripts.slice.register Save a session slice for focused transcript review

    When to use:

      sync       After importing new transcript files or re-syncing a session
      search     To find slow, failing, or specific tool calls across sessions
      inspect    To drill into a single session's tool call timeline
      compare    To compare tool usage patterns between session groups
      slice.register  To bookmark interesting parts of a session for later review

    Run any command with --help or no arguments for usage details.
    Full documentation: docs/telemetry/transcript-analytics-cli.md
    """)
  end
end
