defmodule Mix.Tasks.Spotter.Transcripts.Sync do
  @moduledoc "Sync transcripts from JSONL files, then derive tool call runs."
  @shortdoc "Sync transcripts and derive tool call runs"
  use Mix.Task

  alias Spotter.Services.TranscriptAnalytics

  alias Spotter.Transcripts.Jobs.SyncTranscripts
  alias Spotter.Transcripts.Session

  require Ash.Query

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

    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          session: :string,
          file: :string,
          transcript_root: :string
        ]
      )

    cond do
      opts[:session] ->
        result = SyncTranscripts.sync_session_by_id(opts[:session])
        derive_for_session_id(opts[:session])

        Mix.shell().info(
          "Sync for session #{opts[:session]}: #{result.status}, #{result.ingested_messages} messages."
        )

      opts[:file] ->
        result = SyncTranscripts.sync_session_file(opts[:file])
        if result.session_id, do: derive_for_session_id(result.session_id)

        Mix.shell().info(
          "Sync from file #{opts[:file]}: #{result.status}, #{result.ingested_messages} messages."
        )

      opts[:transcript_root] ->
        Mix.shell().info("Error: --transcript-root is not yet implemented.")
        Mix.shell().info("Use --session or --file to sync specific transcripts.")

      true ->
        print_usage()
    end
  end

  defp print_usage do
    Mix.shell().info("""
    Usage: mix spotter.transcripts.sync [options]

    Import/re-import transcripts and derive tool call runs.

    Options:
      --session <id>            Sync a specific session by external ID
      --file <path>             Sync from a specific JSONL transcript file
      --transcript-root <path>  Sync all sessions under a transcript root (not yet implemented)
    """)
  end

  defp derive_for_session_id(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %Session{} = session} ->
        count = TranscriptAnalytics.derive_runs!(session)
        Mix.shell().info("Derived #{count} tool call runs.")

      _ ->
        :ok
    end
  end
end
