defmodule Mix.Tasks.Spotter.E2e.SeedTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 180_000

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Message, Session, ToolCall}

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)

    temp_root =
      Path.join(System.tmp_dir!(), "spotter-e2e-seed-#{System.unique_integer([:positive])}")

    temp_home = Path.join(temp_root, "home")
    fixture_root = Path.join(temp_root, "fixtures")

    File.mkdir_p!(temp_home)
    File.mkdir_p!(fixture_root)

    fixture_source = Path.expand("test/fixtures/transcripts", File.cwd!())

    copy_fixture!(fixture_source, fixture_root, "short.jsonl")
    copy_fixture!(fixture_source, fixture_root, "tool_heavy.jsonl")

    original_home = System.get_env("HOME")
    original_fixture_root = System.get_env("SPOTTER_E2E_FIXTURE_ROOT")

    System.put_env("HOME", temp_home)
    System.put_env("SPOTTER_E2E_FIXTURE_ROOT", fixture_root)

    on_exit(fn ->
      Sandbox.stop_owner(pid)
      restore_env("HOME", original_home)
      restore_env("SPOTTER_E2E_FIXTURE_ROOT", original_fixture_root)
      File.rm_rf!(temp_root)
    end)

    :ok
  end

  @tag :slow
  test "copies fixtures and stays idempotent for session/message/tool_call counts" do
    Mix.Task.reenable("spotter.e2e.seed")

    capture_io(fn ->
      Mix.Task.run("spotter.e2e.seed")
    end)

    assert File.regular?(Path.join(seed_target_dir(), "short.jsonl"))
    assert File.regular?(Path.join(seed_target_dir(), "tool_heavy.jsonl"))
    assert count(Session) > 0

    first_counts = snapshot_counts()

    Mix.Task.reenable("spotter.e2e.seed")

    capture_io(fn ->
      Mix.Task.run("spotter.e2e.seed")
    end)

    assert snapshot_counts() == first_counts
  end

  defp seed_target_dir do
    Path.join([System.user_home!(), ".claude/projects/-home-marco-projects-spotter"])
  end

  defp snapshot_counts do
    %{
      sessions: count(Session),
      messages: count(Message),
      tool_calls: count(ToolCall)
    }
  end

  defp count(resource) do
    table =
      case resource do
        Session -> "sessions"
        Message -> "messages"
        ToolCall -> "tool_calls"
      end

    %{rows: [[count]]} = Repo.query!("SELECT COUNT(*) FROM #{table}")
    count
  end

  defp copy_fixture!(source_root, dest_root, filename) do
    source = Path.join(source_root, filename)
    destination = Path.join(dest_root, filename)
    File.cp!(source, destination)
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
