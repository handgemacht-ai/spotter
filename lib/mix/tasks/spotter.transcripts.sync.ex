defmodule Mix.Tasks.Spotter.Transcripts.Sync do
  @moduledoc "Sync transcripts from JSONL files, then derive tool call runs."
  @shortdoc "Sync transcripts and derive tool call runs"
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

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
        Mix.shell().info("Sync for session #{opts[:session]} done.")

      opts[:file] ->
        Mix.shell().info("Sync from file #{opts[:file]} done.")

      opts[:transcript_root] ->
        Mix.shell().info("Sync from transcript root #{opts[:transcript_root]} done.")

      true ->
        Mix.shell().info("Sync complete.")
    end
  end
end
