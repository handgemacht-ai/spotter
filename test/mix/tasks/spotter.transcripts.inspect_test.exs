defmodule Mix.Tasks.Spotter.Transcripts.InspectTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "option parsing" do
    test "requires --session option" do
      Mix.Task.reenable("spotter.transcripts.inspect")

      assert_raise Mix.Error, ~r/--session/i, fn ->
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.inspect", [])
        end)
      end
    end

    test "accepts --session option" do
      Mix.Task.reenable("spotter.transcripts.inspect")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.inspect", [
            "--session",
            "abc-123"
          ])
        end)

      assert is_binary(output)
    end

    test "accepts --tool-use-id option" do
      Mix.Task.reenable("spotter.transcripts.inspect")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.inspect", [
            "--session",
            "abc-123",
            "--tool-use-id",
            "toolu_xyz"
          ])
        end)

      assert is_binary(output)
    end

    test "accepts --context option for surrounding lines" do
      Mix.Task.reenable("spotter.transcripts.inspect")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.inspect", [
            "--session",
            "abc-123",
            "--context",
            "5"
          ])
        end)

      assert is_binary(output)
    end
  end

  describe "output formats" do
    test "supports --format table (default)" do
      Mix.Task.reenable("spotter.transcripts.inspect")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.inspect", [
            "--session",
            "abc-123",
            "--format",
            "table"
          ])
        end)

      assert is_binary(output)
    end

    test "supports --format json" do
      Mix.Task.reenable("spotter.transcripts.inspect")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.transcripts.inspect", [
            "--session",
            "abc-123",
            "--format",
            "json"
          ])
        end)

      assert is_binary(output)
    end
  end
end
