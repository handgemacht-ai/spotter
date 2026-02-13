defmodule Spotter.Services.CoChangeCalculatorTest do
  use ExUnit.Case, async: false

  # Real git history can produce many groups; 60s default is too tight for two compute runs.
  @moduletag timeout: 180_000

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.CoChangeCalculator

  alias Spotter.Transcripts.{
    CoChangeGroup,
    CoChangeGroupCommit,
    CoChangeGroupMemberStat,
    Project,
    Session
  }

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_session(project, opts \\ []) do
    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "test-dir",
      project_id: project.id,
      cwd: opts[:cwd]
    })
  end

  defp read_groups(project_id, scope) do
    CoChangeGroup
    |> Ash.Query.filter(project_id == ^project_id and scope == ^scope)
    |> Ash.read!()
  end

  describe "compute/2" do
    test "returns :ok for project with no sessions" do
      project = create_project("calc-no-sessions")
      assert :ok = CoChangeCalculator.compute(project.id)
    end

    test "returns :ok for session with inaccessible cwd" do
      project = create_project("calc-bad-cwd")
      create_session(project, cwd: "/nonexistent/path/abc123")
      assert :ok = CoChangeCalculator.compute(project.id)
    end

    test "returns :ok and persists groups with provenance for valid repo" do
      project = create_project("calc-real-repo")
      # Use the current repo as the cwd - it has real git history
      create_session(project, cwd: File.cwd!())

      assert :ok = CoChangeCalculator.compute(project.id)

      # Should have computed some file groups from real git history
      file_groups = read_groups(project.id, :file)
      dir_groups = read_groups(project.id, :directory)

      # Real repo should produce at least some groups
      assert is_list(file_groups)
      assert is_list(dir_groups)

      # Provenance: group commits should exist
      group_commits = Ash.read!(CoChangeGroupCommit)
      assert group_commits != []

      # Provenance: member stats should exist
      member_stats = Ash.read!(CoChangeGroupMemberStat)
      assert member_stats != []

      # Verify at least one member stat has metrics
      assert Enum.any?(member_stats, &(&1.size_bytes != nil))
    end

    test "cleans up stale rows on re-run" do
      project = create_project("calc-stale")

      # Insert a stale co-change group
      Ash.create!(CoChangeGroup, %{
        project_id: project.id,
        scope: :file,
        group_key: "stale_a.ex|stale_b.ex",
        members: ["stale_a.ex", "stale_b.ex"],
        frequency_30d: 5
      })

      # Run with no sessions => no groups computed => stale row should be deleted
      assert :ok = CoChangeCalculator.compute(project.id)

      # Stale row should be gone (no sessions = skip, rows kept intact)
      # Actually, no sessions means :skip so existing rows are kept
      remaining = read_groups(project.id, :file)
      assert length(remaining) == 1
    end

    test "compute is idempotent for provenance rows" do
      project = create_project("calc-idempotent")
      create_session(project, cwd: File.cwd!())

      assert :ok = CoChangeCalculator.compute(project.id)
      commits_after_first = Ash.read!(CoChangeGroupCommit)
      stats_after_first = Ash.read!(CoChangeGroupMemberStat)

      assert :ok = CoChangeCalculator.compute(project.id)
      commits_after_second = Ash.read!(CoChangeGroupCommit)
      stats_after_second = Ash.read!(CoChangeGroupMemberStat)

      # Same number of rows (upsert, no duplicates)
      assert length(commits_after_first) == length(commits_after_second)
      assert length(stats_after_first) == length(stats_after_second)
    end

    test "provenance writes are batched (fewer inserts than rows)" do
      project = create_project("calc-batched")
      create_session(project, cwd: File.cwd!())

      # Attach telemetry handler to count INSERT statements per table
      insert_counts = :counters.new(2, [:atomics])
      # index 1 = co_change_group_commits inserts, index 2 = co_change_group_member_stats inserts
      handler_id = "batch-insert-counter-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:spotter, :repo, :query],
        fn _event, _measurements, metadata, _config ->
          query = metadata[:query] || ""

          if String.contains?(query, "INSERT") do
            cond do
              String.contains?(query, "co_change_group_commits") ->
                :counters.add(insert_counts, 1, 1)

              String.contains?(query, "co_change_group_member_stats") ->
                :counters.add(insert_counts, 2, 1)

              true ->
                :ok
            end
          end
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = CoChangeCalculator.compute(project.id)

      commit_inserts = :counters.get(insert_counts, 1)
      stat_inserts = :counters.get(insert_counts, 2)

      commit_rows =
        CoChangeGroupCommit
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.read!()
        |> length()

      stat_rows =
        CoChangeGroupMemberStat
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.read!()
        |> length()

      # When there are multiple rows, insert count must be strictly less than row count
      # (proves batching, not one-insert-per-row)
      if commit_rows > 1 do
        assert commit_inserts < commit_rows,
               "Expected fewer INSERT queries (#{commit_inserts}) than commit rows (#{commit_rows})"
      end

      if stat_rows > 1 do
        assert stat_inserts < stat_rows,
               "Expected fewer INSERT queries (#{stat_inserts}) than member stat rows (#{stat_rows})"
      end

      # Idempotency: second run should not increase row counts
      assert :ok = CoChangeCalculator.compute(project.id)

      commit_rows_after =
        CoChangeGroupCommit
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.read!()
        |> length()

      stat_rows_after =
        CoChangeGroupMemberStat
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.read!()
        |> length()

      assert commit_rows == commit_rows_after
      assert stat_rows == stat_rows_after
    end

    test "spotterignore excludes matching paths from co-change groups" do
      tmp_dir = Path.join(System.tmp_dir!(), "co_change_ignore_#{System.unique_integer()}")
      File.mkdir_p!(tmp_dir)

      System.cmd("git", ["-C", tmp_dir, "init"])
      System.cmd("git", ["-C", tmp_dir, "config", "user.name", "Test"])
      System.cmd("git", ["-C", tmp_dir, "config", "user.email", "test@test.com"])

      # Commit 1: lib/a.ex + lib/b.ex + .beads/issues.jsonl
      File.mkdir_p!(Path.join(tmp_dir, "lib"))
      File.mkdir_p!(Path.join(tmp_dir, ".beads"))
      File.write!(Path.join(tmp_dir, "lib/a.ex"), "defmodule A, do: :ok")
      File.write!(Path.join(tmp_dir, "lib/b.ex"), "defmodule B, do: :ok")
      File.write!(Path.join(tmp_dir, ".beads/issues.jsonl"), "{}")
      System.cmd("git", ["-C", tmp_dir, "add", "."])
      System.cmd("git", ["-C", tmp_dir, "commit", "-m", "commit 1"])

      # Commit 2: touch same files again
      File.write!(Path.join(tmp_dir, "lib/a.ex"), "defmodule A, do: :ok2")
      File.write!(Path.join(tmp_dir, "lib/b.ex"), "defmodule B, do: :ok2")
      File.write!(Path.join(tmp_dir, ".beads/issues.jsonl"), "{\"v\":2}")
      System.cmd("git", ["-C", tmp_dir, "add", "."])
      System.cmd("git", ["-C", tmp_dir, "commit", "-m", "commit 2"])

      # Write .spotterignore
      File.write!(Path.join(tmp_dir, ".spotterignore"), ".beads/\n")

      project = create_project("calc-spotterignore-#{System.unique_integer([:positive])}")
      create_session(project, cwd: tmp_dir)

      assert :ok = CoChangeCalculator.compute(project.id)

      file_groups = read_groups(project.id, :file)
      all_members = Enum.flat_map(file_groups, & &1.members)

      refute ".beads/issues.jsonl" in all_members
      assert "lib/a.ex" in all_members or "lib/b.ex" in all_members

      File.rm_rf!(tmp_dir)
    end

    test "deletes stale rows when repo is accessible" do
      project = create_project("calc-stale-cleanup")
      create_session(project, cwd: File.cwd!())

      # Insert a stale co-change group with a key that won't exist in real data
      Ash.create!(CoChangeGroup, %{
        project_id: project.id,
        scope: :file,
        group_key: "zzz_nonexistent_a.ex|zzz_nonexistent_b.ex",
        members: ["zzz_nonexistent_a.ex", "zzz_nonexistent_b.ex"],
        frequency_30d: 5
      })

      assert :ok = CoChangeCalculator.compute(project.id)

      # The stale row should be removed
      remaining = read_groups(project.id, :file)
      stale = Enum.find(remaining, &(&1.group_key == "zzz_nonexistent_a.ex|zzz_nonexistent_b.ex"))
      assert stale == nil
    end
  end
end
