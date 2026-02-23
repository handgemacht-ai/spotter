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
    copy_fixture_dir!(fixture_source, fixture_root, "team-overlap")

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

    %{fixture_root: fixture_root}
  end

  @moduletag :slow

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

  describe "--scenario flag" do
    test "seeds only team-overlap fixtures when --scenario team-overlap" do
      Mix.Task.reenable("spotter.e2e.seed")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.e2e.seed", ["--scenario", "team-overlap"])
        end)

      assert output =~ "scenario: team-overlap"
      assert output =~ "copied_jsonl_files: 3"

      # Verify the 3 team-overlap files were copied to the target dir
      target = seed_target_dir()

      for uuid <- ~w(
        00000000-0000-0000-0000-000000000001
        00000000-0000-0000-0000-000000000002
        00000000-0000-0000-0000-000000000003
      ) do
        assert File.regular?(Path.join(target, "#{uuid}.jsonl")),
               "Expected #{uuid}.jsonl to be copied to target"
      end
    end

    test "scenario seed creates a clean target dir with only scenario files" do
      # First seed all
      Mix.Task.reenable("spotter.e2e.seed")

      capture_io(fn ->
        Mix.Task.run("spotter.e2e.seed")
      end)

      assert File.regular?(Path.join(seed_target_dir(), "short.jsonl"))

      # Scenario seed wipes and replaces with only scenario files
      Mix.Task.reenable("spotter.e2e.seed")

      capture_io(fn ->
        Mix.Task.run("spotter.e2e.seed", ["--scenario", "team-overlap"])
      end)

      refute File.regular?(Path.join(seed_target_dir(), "short.jsonl")),
             "Scenario seed should wipe non-scenario files"

      assert File.regular?(
               Path.join(seed_target_dir(), "00000000-0000-0000-0000-000000000001.jsonl")
             )
    end

    test "raises on unknown scenario" do
      Mix.Task.reenable("spotter.e2e.seed")

      assert_raise Mix.Error, ~r/Unknown scenario: nonexistent/, fn ->
        capture_io(fn ->
          Mix.Task.run("spotter.e2e.seed", ["--scenario", "nonexistent"])
        end)
      end
    end
  end

  describe "--cleanup flag" do
    test "outputs correct scenario label and session count, handles empty DB" do
      Mix.Task.reenable("spotter.e2e.seed")

      output =
        capture_io(fn ->
          Mix.Task.run("spotter.e2e.seed", ["--cleanup", "--scenario", "team-overlap"])
        end)

      assert output =~ "Cleaned up"
      assert output =~ "scenario: team-overlap"
      assert output =~ "session_ids: 3"
    end

    test "removes exactly the scenario sessions from the database" do
      before_counts = snapshot_counts()

      # Seed team-overlap
      Mix.Task.reenable("spotter.e2e.seed")

      capture_io(fn ->
        Mix.Task.run("spotter.e2e.seed", ["--scenario", "team-overlap"])
      end)

      # Verify seeding added sessions
      assert count(Session) > before_counts.sessions

      # Verify the deterministic UUIDs are present
      for uuid <- ~w(
        00000000-0000-0000-0000-000000000001
        00000000-0000-0000-0000-000000000002
        00000000-0000-0000-0000-000000000003
      ) do
        assert %{rows: [[1]]} =
                 Repo.query!("SELECT COUNT(*) FROM sessions WHERE session_id = $1", [uuid])
      end

      # Now cleanup
      Mix.Task.reenable("spotter.e2e.seed")

      capture_io(fn ->
        Mix.Task.run("spotter.e2e.seed", ["--cleanup", "--scenario", "team-overlap"])
      end)

      # Counts should return to pre-seed baseline
      assert snapshot_counts() == before_counts

      # Verify the deterministic UUIDs are gone
      for uuid <- ~w(
        00000000-0000-0000-0000-000000000001
        00000000-0000-0000-0000-000000000002
        00000000-0000-0000-0000-000000000003
      ) do
        assert %{rows: [[0]]} =
                 Repo.query!("SELECT COUNT(*) FROM sessions WHERE session_id = $1", [uuid])
      end
    end
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

  defp copy_fixture_dir!(source_root, dest_root, dirname) do
    source = Path.join(source_root, dirname)
    destination = Path.join(dest_root, dirname)
    File.cp_r!(source, destination)
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
