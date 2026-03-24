defmodule Mix.Tasks.Spotter.TranscriptsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  test "lists all available subcommands" do
    Mix.Task.reenable("spotter.transcripts")

    output =
      capture_io(fn ->
        Mix.Task.run("spotter.transcripts", [])
      end)

    assert output =~ "spotter.transcripts.sync"
    assert output =~ "spotter.transcripts.search"
    assert output =~ "spotter.transcripts.inspect"
    assert output =~ "spotter.transcripts.compare"
    assert output =~ "spotter.transcripts.slice.register"
  end
end
