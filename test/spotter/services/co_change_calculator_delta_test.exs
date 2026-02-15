defmodule Spotter.Services.CoChangeCalculatorDeltaTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.CoChangeCalculator
  alias Spotter.TestSupport.GitRepoHelper

  alias Spotter.Transcripts.{
    CoChangeGroup,
    CoChangeGroupCommit,
    Project,
    ProjectIngestState,
    Session
  }

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_session(project, opts) do
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

  defp read_group_commits(project_id, scope) do
    CoChangeGroupCommit
    |> Ash.Query.filter(project_id == ^project_id and scope == ^scope)
    |> Ash.read!()
  end

  defp clear_watermark(project_id) do
    ProjectIngestState
    |> Ash.Query.filter(project_id == ^project_id)
    |> Ash.read!()
    |> Enum.each(fn state ->
      Ash.update!(state, %{co_change_last_run_at: nil})
    end)
  end

  defp group_map(project_id, scope) do
    read_groups(project_id, scope)
    |> Map.new(fn g -> {g.group_key, g} end)
  end

  describe "delta mode" do
    test "delta vs full rebuild consistency for pairs" do
      # Two commits both touching lib/a.ex + lib/b.ex -> co-change pair
      t0 = ~U[2026-02-01 10:00:00Z]
      t1_commit = ~U[2026-02-01 11:00:00Z]

      repo_path =
        GitRepoHelper.create_repo_with_timed_history!([
          {t0, [{"lib/a.ex", "mod A v1"}, {"lib/b.ex", "mod B v1"}]},
          {t1_commit, [{"lib/a.ex", "mod A v2"}, {"lib/b.ex", "mod B v2"}]}
        ])

      on_exit(fn -> File.rm_rf!(repo_path) end)

      project = create_project("delta-consistency-#{System.unique_integer([:positive])}")
      create_session(project, cwd: repo_path)

      # Full rebuild at t1
      t1 = ~U[2026-02-01 12:00:00Z]
      assert :ok = CoChangeCalculator.compute(project.id, reference_date: t1)
      after_full = group_map(project.id, :file)
      assert Map.has_key?(after_full, "lib/a.ex|lib/b.ex")
      assert after_full["lib/a.ex|lib/b.ex"].frequency_30d == 2

      # Delta at t2 (no new commits) should be idempotent
      t2 = ~U[2026-02-01 14:00:00Z]
      assert :ok = CoChangeCalculator.compute(project.id, reference_date: t2)
      after_delta = group_map(project.id, :file)

      assert after_delta["lib/a.ex|lib/b.ex"].frequency_30d == 2

      # Clear watermark and run full at t2, compare
      clear_watermark(project.id)
      assert :ok = CoChangeCalculator.compute(project.id, reference_date: t2)
      after_full_t2 = group_map(project.id, :file)

      assert after_delta["lib/a.ex|lib/b.ex"].frequency_30d ==
               after_full_t2["lib/a.ex|lib/b.ex"].frequency_30d
    end

    test "delta adds new commit pairs" do
      # Start with one commit (not enough for a pair group, need freq >= 2)
      t0 = ~U[2026-02-01 10:00:00Z]

      repo_path =
        GitRepoHelper.create_repo_with_timed_history!([
          {t0, [{"lib/a.ex", "mod A v1"}, {"lib/b.ex", "mod B v1"}]}
        ])

      on_exit(fn -> File.rm_rf!(repo_path) end)

      project = create_project("delta-add-#{System.unique_integer([:positive])}")
      create_session(project, cwd: repo_path)

      # Full at t1 (only 1 commit, pair has freq=1, no group)
      t1 = ~U[2026-02-01 12:00:00Z]
      assert :ok = CoChangeCalculator.compute(project.id, reference_date: t1)
      after_full = group_map(project.id, :file)
      # Full rebuild uses CoChangeIntersections which requires freq >= 2
      # With only 1 commit, there should be no group (or the group might exist
      # from the intersection algorithm but with freq=1... let's check)
      # Actually the intersection algo only returns groups with freq >= 1 (it counts supporting commits)
      # but the pair needs 2 commits to appear. With 1 commit, the intersection
      # with itself doesn't produce candidates (needs 2 distinct commit sets).
      refute Map.has_key?(after_full, "lib/a.ex|lib/b.ex")

      # Add second commit at t1 + 1h
      t_new = ~U[2026-02-01 13:00:00Z]

      add_commit_to_repo!(repo_path, t_new, [
        {"lib/a.ex", "mod A v2"},
        {"lib/b.ex", "mod B v2"}
      ])

      # Delta at t2 should pick up the new commit and create the pair
      t2 = ~U[2026-02-01 15:00:00Z]
      assert :ok = CoChangeCalculator.compute(project.id, reference_date: t2)
      after_delta = group_map(project.id, :file)

      assert Map.has_key?(after_delta, "lib/a.ex|lib/b.ex")
      assert after_delta["lib/a.ex|lib/b.ex"].frequency_30d == 2

      # Verify group commits exist
      commits = read_group_commits(project.id, :file)
      pair_commits = Enum.filter(commits, &(&1.group_key == "lib/a.ex|lib/b.ex"))
      assert length(pair_commits) == 2
    end

    test "delta removes aged-out commits" do
      # Create commits near window boundary
      t_old1 = ~U[2026-01-02 10:00:00Z]
      t_old2 = ~U[2026-01-02 11:00:00Z]
      t_recent = ~U[2026-01-20 10:00:00Z]

      repo_path =
        GitRepoHelper.create_repo_with_timed_history!([
          {t_old1, [{"lib/a.ex", "mod A v1"}, {"lib/b.ex", "mod B v1"}]},
          {t_old2, [{"lib/a.ex", "mod A v2"}, {"lib/b.ex", "mod B v2"}]},
          {t_recent, [{"lib/c.ex", "mod C v1"}, {"lib/d.ex", "mod D v1"}]}
        ])

      on_exit(fn -> File.rm_rf!(repo_path) end)

      project = create_project("delta-expire-#{System.unique_integer([:positive])}")
      create_session(project, cwd: repo_path)

      # Full at t1 (window: Jan 1 - Jan 31) - both old commits in window
      t1 = ~U[2026-01-31 12:00:00Z]
      assert :ok = CoChangeCalculator.compute(project.id, reference_date: t1)
      after_full = group_map(project.id, :file)
      assert Map.has_key?(after_full, "lib/a.ex|lib/b.ex")
      assert after_full["lib/a.ex|lib/b.ex"].frequency_30d == 2

      # Delta at t2 (window: Jan 4 - Feb 3) - old commits aged out
      t2 = ~U[2026-02-03 12:00:00Z]
      assert :ok = CoChangeCalculator.compute(project.id, reference_date: t2)
      after_delta = group_map(project.id, :file)

      # lib/a.ex|lib/b.ex should be gone (both commits expired, freq < 2)
      refute Map.has_key?(after_delta, "lib/a.ex|lib/b.ex")

      # Group commits should be cleaned up too
      pair_commits =
        read_group_commits(project.id, :file)
        |> Enum.filter(&(&1.group_key == "lib/a.ex|lib/b.ex"))

      assert pair_commits == []
    end

    test "fallback to full when watermark is stale" do
      t0 = ~U[2026-02-01 10:00:00Z]
      t1 = ~U[2026-02-01 11:00:00Z]

      repo_path =
        GitRepoHelper.create_repo_with_timed_history!([
          {t0, [{"lib/a.ex", "mod A v1"}, {"lib/b.ex", "mod B v1"}]},
          {t1, [{"lib/a.ex", "mod A v2"}, {"lib/b.ex", "mod B v2"}]}
        ])

      on_exit(fn -> File.rm_rf!(repo_path) end)

      project = create_project("delta-fallback-#{System.unique_integer([:positive])}")
      create_session(project, cwd: repo_path)

      # Manually inject a very old watermark (> 30 days before reference)
      Ash.create!(ProjectIngestState, %{
        project_id: project.id,
        co_change_last_run_at: ~U[2025-12-01 00:00:00Z],
        co_change_window_days: 30
      })

      # Compute should fall back to full and still produce correct results
      t_ref = ~U[2026-02-01 14:00:00Z]
      assert :ok = CoChangeCalculator.compute(project.id, reference_date: t_ref)

      groups = group_map(project.id, :file)
      assert Map.has_key?(groups, "lib/a.ex|lib/b.ex")
      assert groups["lib/a.ex|lib/b.ex"].frequency_30d == 2

      # Watermark should be updated
      [state] =
        ProjectIngestState
        |> Ash.Query.filter(project_id == ^project.id)
        |> Ash.read!()

      assert DateTime.compare(state.co_change_last_run_at, t_ref) == :eq
    end

    test "large commit guardrail skips pair explosion" do
      # Start with a small repo (full rebuild is fast)
      t0 = ~U[2026-02-01 10:00:00Z]
      t1 = ~U[2026-02-01 11:00:00Z]

      repo_path =
        GitRepoHelper.create_repo_with_timed_history!([
          {t0, [{"lib/a.ex", "mod A v1"}, {"lib/b.ex", "mod B v1"}]},
          {t1, [{"lib/a.ex", "mod A v2"}, {"lib/b.ex", "mod B v2"}]}
        ])

      on_exit(fn -> File.rm_rf!(repo_path) end)

      project = create_project("delta-guardrail-#{System.unique_integer([:positive])}")
      create_session(project, cwd: repo_path)

      # Full rebuild with small repo
      t_ref = ~U[2026-02-01 12:00:00Z]
      assert :ok = CoChangeCalculator.compute(project.id, reference_date: t_ref)
      before_groups = read_groups(project.id, :file)

      # Add a commit touching > 100 files
      large_files =
        for i <- 1..105 do
          {"lib/file_#{String.pad_leading("#{i}", 3, "0")}.ex", "mod F#{i}"}
        end

      t_new = ~U[2026-02-01 13:00:00Z]
      add_commit_to_repo!(repo_path, t_new, large_files)

      # Delta should skip the large commit (no new pairs from it)
      t2 = ~U[2026-02-01 15:00:00Z]
      assert :ok = CoChangeCalculator.compute(project.id, reference_date: t2)

      # Groups should be unchanged (large commit was skipped)
      after_groups = read_groups(project.id, :file)
      assert length(before_groups) == length(after_groups)
    end

    test "delta works for directory scope" do
      t0 = ~U[2026-02-01 10:00:00Z]
      t1 = ~U[2026-02-01 11:00:00Z]

      repo_path =
        GitRepoHelper.create_repo_with_timed_history!([
          {t0, [{"lib/a.ex", "mod A v1"}, {"src/b.ex", "mod B v1"}]},
          {t1, [{"lib/a.ex", "mod A v2"}, {"src/b.ex", "mod B v2"}]}
        ])

      on_exit(fn -> File.rm_rf!(repo_path) end)

      project = create_project("delta-dir-#{System.unique_integer([:positive])}")
      create_session(project, cwd: repo_path)

      # Full at t1
      t_ref = ~U[2026-02-01 12:00:00Z]
      assert :ok = CoChangeCalculator.compute(project.id, reference_date: t_ref)

      dir_groups = group_map(project.id, :directory)
      assert Map.has_key?(dir_groups, "lib|src")
      assert dir_groups["lib|src"].frequency_30d == 2

      # Delta at t2 with no changes should be consistent
      t2 = ~U[2026-02-01 14:00:00Z]
      assert :ok = CoChangeCalculator.compute(project.id, reference_date: t2)

      dir_groups_after = group_map(project.id, :directory)
      assert dir_groups_after["lib|src"].frequency_30d == 2
    end
  end

  # Helper to add a commit to an existing repo at a specific time
  defp add_commit_to_repo!(repo_path, %DateTime{} = dt, files) do
    Enum.each(files, fn {path, content} ->
      full_path = Path.join(repo_path, path)
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, content)
    end)

    {_, 0} = System.cmd("git", ["-C", repo_path, "add", "."])
    iso = DateTime.to_iso8601(dt)

    {_, 0} =
      System.cmd("git", ["-C", repo_path, "commit", "-m", "commit at #{iso}"],
        env: [{"GIT_AUTHOR_DATE", iso}, {"GIT_COMMITTER_DATE", iso}]
      )
  end
end
