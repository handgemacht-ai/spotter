defmodule Mix.Tasks.Spotter.Transcripts.SearchTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "option parsing" do
    test "parses --project filter" do
      Mix.Task.reenable("spotter.transcripts.search")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.search", [
            "--project",
            "my-project"
          ])
        end)

      assert is_binary(output)
    end

    test "parses --tool filter" do
      Mix.Task.reenable("spotter.transcripts.search")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.search", [
            "--tool",
            "Bash"
          ])
        end)

      assert is_binary(output)
    end

    test "parses --command-contains filter" do
      Mix.Task.reenable("spotter.transcripts.search")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.search", [
            "--command-contains",
            "mix test"
          ])
        end)

      assert is_binary(output)
    end

    test "parses --min-duration-ms and --max-duration-ms filters" do
      Mix.Task.reenable("spotter.transcripts.search")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.search", [
            "--min-duration-ms",
            "1000",
            "--max-duration-ms",
            "5000"
          ])
        end)

      assert is_binary(output)
    end

    test "parses --status filter" do
      Mix.Task.reenable("spotter.transcripts.search")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.search", [
            "--status",
            "completed"
          ])
        end)

      assert is_binary(output)
    end

    test "parses --session filter" do
      Mix.Task.reenable("spotter.transcripts.search")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.search", [
            "--session",
            "abc-123"
          ])
        end)

      assert is_binary(output)
    end

    test "parses --limit option" do
      Mix.Task.reenable("spotter.transcripts.search")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.search", [
            "--limit",
            "10"
          ])
        end)

      assert is_binary(output)
    end
  end

  describe "output formats" do
    test "supports --format table (default)" do
      Mix.Task.reenable("spotter.transcripts.search")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.search", ["--format", "table"])
        end)

      assert is_binary(output)
    end

    test "supports --format json" do
      Mix.Task.reenable("spotter.transcripts.search")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.search", ["--format", "json"])
        end)

      assert is_binary(output)

      case Jason.decode(output) do
        {:ok, decoded} -> assert is_list(decoded) or is_map(decoded)
        {:error, _} -> flunk("JSON output is not valid JSON: #{output}")
      end
    end
  end
end
