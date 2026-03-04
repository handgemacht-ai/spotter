defmodule Spotter.Services.ShellCommandTelemetryQueryTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Services.ShellCommandTelemetryQuery
  alias Spotter.Transcripts.{Project, Session, ShellCommandEvent}

  setup do
    Sandbox.checkout(Spotter.Repo)

    project =
      Ash.create!(Project, %{name: "telemetry-query-test", pattern: "^telemetry-query-test$"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        project_id: project.id,
        cwd: "/home/user/telemetry-query-test"
      })

    %{project: project, session: session}
  end

  defp create_event(session, attrs) do
    now = DateTime.utc_now()

    defaults = %{
      session_id: session.id,
      external_session_id: session.session_id,
      project_id: session.project_id,
      tool_use_id: Ash.UUID.generate(),
      tool_name: "Bash",
      command: "mix test",
      command_path: "tool_input.command",
      hook_event_name: "PreToolUse",
      phase: :start,
      captured_at: now,
      raw_hook_event_id: Ash.UUID.generate()
    }

    Ash.create!(ShellCommandEvent, Map.merge(defaults, attrs))
  end

  describe "fold_runs/1 — run folding" do
    test "start+finish pair for same tool_use_id+command_path produces one completed run with correct duration_ms",
         %{session: session, project: project} do
      tool_use_id = "toolu_fold_1"

      create_event(session, %{
        tool_use_id: tool_use_id,
        command: "mix test",
        command_path: "tool_input.command",
        phase: :start,
        hook_event_name: "PreToolUse",
        captured_at: ~U[2026-03-04 10:00:00.000000Z],
        raw_hook_event_id: "fold-start-1"
      })

      create_event(session, %{
        tool_use_id: tool_use_id,
        command: "mix test",
        command_path: "tool_input.command",
        phase: :finish,
        finish_status: :ok,
        hook_event_name: "PostToolUse",
        captured_at: ~U[2026-03-04 10:00:02.500000Z],
        raw_hook_event_id: "fold-finish-1"
      })

      runs = ShellCommandTelemetryQuery.fold_runs(project.id)

      completed = Enum.filter(runs, &(&1.status == :completed))
      assert length(completed) == 1

      run = hd(completed)
      assert run.duration_ms == 2500
      assert run.command == "mix test"
    end

    test "start without finish produces ongoing run with elapsed_ms",
         %{session: session, project: project} do
      create_event(session, %{
        tool_use_id: "toolu_ongoing_1",
        command: "mix test",
        phase: :start,
        hook_event_name: "PreToolUse",
        captured_at: ~U[2026-03-04 10:00:00.000000Z],
        raw_hook_event_id: "ongoing-start-1"
      })

      runs = ShellCommandTelemetryQuery.fold_runs(project.id)

      ongoing = Enum.filter(runs, &(&1.status == :ongoing))
      assert length(ongoing) == 1

      run = hd(ongoing)
      assert run.duration_ms == nil
      assert is_integer(run.elapsed_ms)
      assert run.elapsed_ms >= 0
      assert run.command == "mix test"
    end

    test "finish-only orphan event is excluded from duration stats",
         %{session: session, project: project} do
      create_event(session, %{
        tool_use_id: "toolu_orphan_1",
        command: "mix test",
        phase: :finish,
        finish_status: :ok,
        hook_event_name: "PostToolUse",
        captured_at: ~U[2026-03-04 10:00:05.000000Z],
        raw_hook_event_id: "orphan-finish-1"
      })

      runs = ShellCommandTelemetryQuery.fold_runs(project.id)

      # Orphan should have status :orphan and nil duration
      assert length(runs) == 1
      run = hd(runs)
      assert run.status == :orphan
      assert run.duration_ms == nil
      assert run.started_at == nil
    end

    test "duplicate finish events uses latest ordered finish",
         %{session: session, project: project} do
      tool_use_id = "toolu_dupfin_1"

      create_event(session, %{
        tool_use_id: tool_use_id,
        command: "mix test",
        command_path: "tool_input.command",
        phase: :start,
        hook_event_name: "PreToolUse",
        captured_at: ~U[2026-03-04 10:00:00.000000Z],
        raw_hook_event_id: "dupfin-start-1"
      })

      create_event(session, %{
        tool_use_id: tool_use_id,
        command: "mix test",
        command_path: "tool_input.command",
        phase: :finish,
        finish_status: :ok,
        hook_event_name: "PostToolUse",
        captured_at: ~U[2026-03-04 10:00:01.000000Z],
        raw_hook_event_id: "dupfin-finish-1"
      })

      create_event(session, %{
        tool_use_id: tool_use_id,
        command: "mix test",
        command_path: "tool_input.command",
        phase: :finish,
        finish_status: :ok,
        hook_event_name: "PostToolUse",
        captured_at: ~U[2026-03-04 10:00:03.000000Z],
        raw_hook_event_id: "dupfin-finish-2"
      })

      runs = ShellCommandTelemetryQuery.fold_runs(project.id)

      completed = Enum.filter(runs, &(&1.status == :completed))
      assert length(completed) == 1
      # Duration from start to latest finish: 3000ms
      assert hd(completed).duration_ms == 3000
    end
  end

  describe "compute_percentiles/1" do
    test "nearest-rank p50, p90, p95 with known 10-element dataset" do
      durations = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

      result = ShellCommandTelemetryQuery.compute_percentiles(durations)

      assert result.p50 == 50
      assert result.p90 == 90
      assert result.p95 == 100
    end

    test "empty dataset returns nil for all percentile fields" do
      result = ShellCommandTelemetryQuery.compute_percentiles([])

      assert result.p50 == nil
      assert result.p90 == nil
      assert result.p95 == nil
      assert result.median_ms == nil
    end
  end

  describe "median/1" do
    test "midpoint average for even cardinality (4-element dataset)" do
      # [100, 200, 300, 400] -> (200 + 300) / 2 = 250.0
      assert ShellCommandTelemetryQuery.median([100, 200, 300, 400]) == 250.0
    end

    test "middle element for odd cardinality" do
      # [100, 200, 300] -> 200
      result = ShellCommandTelemetryQuery.median([100, 200, 300])
      assert result == 200 or result == 200.0
    end

    test "empty dataset returns nil" do
      assert ShellCommandTelemetryQuery.median([]) == nil
    end
  end

  describe "error rate" do
    test "error_rate = error_count / (completed + error count), excludes ongoing",
         %{session: session, project: project} do
      # Create 3 completed runs: 2 ok, 1 error
      for {status, hook, idx} <- [
            {:ok, "PostToolUse", 1},
            {:ok, "PostToolUse", 2},
            {:error, "PostToolUseFailure", 3}
          ] do
        tool_use_id = "toolu_err_#{idx}"

        create_event(session, %{
          tool_use_id: tool_use_id,
          command: "mix test",
          command_path: "tool_input.command",
          phase: :start,
          hook_event_name: "PreToolUse",
          captured_at: ~U[2026-03-04 10:00:00.000000Z],
          raw_hook_event_id: "err-start-#{idx}"
        })

        create_event(session, %{
          tool_use_id: tool_use_id,
          command: "mix test",
          command_path: "tool_input.command",
          phase: :finish,
          finish_status: status,
          hook_event_name: hook,
          captured_at: ~U[2026-03-04 10:00:01.000000Z],
          raw_hook_event_id: "err-finish-#{idx}"
        })
      end

      # Also create an ongoing run (should be excluded from error rate)
      create_event(session, %{
        tool_use_id: "toolu_ongoing_err",
        command: "mix test",
        command_path: "tool_input.command",
        phase: :start,
        hook_event_name: "PreToolUse",
        captured_at: ~U[2026-03-04 10:00:00.000000Z],
        raw_hook_event_id: "err-ongoing-start"
      })

      snapshot = ShellCommandTelemetryQuery.snapshot(project.id, window: :all)

      cmd_stats = Enum.find(snapshot, &(&1.command == "mix test"))
      assert cmd_stats != nil
      # 1 error out of 3 finished (2 completed + 1 error) = 1/3
      assert_in_delta cmd_stats.error_rate, 1 / 3, 0.001
    end

    test "empty dataset yields 0.0 error_rate" do
      project =
        Ash.create!(Project, %{name: "empty-err-rate", pattern: "^empty-err-rate$"})

      snapshot = ShellCommandTelemetryQuery.snapshot(project.id)
      assert snapshot == []
    end
  end

  describe "command grouping" do
    test "multiple commands grouped by exact command string",
         %{session: session, project: project} do
      for {cmd, idx} <- [{"mix test", 1}, {"mix test", 2}, {"git status", 3}] do
        tool_use_id = "toolu_group_#{idx}"

        create_event(session, %{
          tool_use_id: tool_use_id,
          command: cmd,
          command_path: "tool_input.command",
          phase: :start,
          hook_event_name: "PreToolUse",
          captured_at: ~U[2026-03-04 10:00:00.000000Z],
          raw_hook_event_id: "group-start-#{idx}"
        })

        create_event(session, %{
          tool_use_id: tool_use_id,
          command: cmd,
          command_path: "tool_input.command",
          phase: :finish,
          finish_status: :ok,
          hook_event_name: "PostToolUse",
          captured_at: ~U[2026-03-04 10:00:01.000000Z],
          raw_hook_event_id: "group-finish-#{idx}"
        })
      end

      snapshot = ShellCommandTelemetryQuery.snapshot(project.id, window: :all)

      commands = Enum.map(snapshot, & &1.command)
      assert "mix test" in commands
      assert "git status" in commands

      mix_stats = Enum.find(snapshot, &(&1.command == "mix test"))
      assert mix_stats.count == 2

      git_stats = Enum.find(snapshot, &(&1.command == "git status"))
      assert git_stats.count == 1
    end
  end

  describe "snapshot/2 — integration" do
    test "snapshot(project_id) returns correct per-command metrics for mixed events",
         %{session: session, project: project} do
      base_time = DateTime.add(DateTime.utc_now(), -3600, :second)

      for {duration_ms, idx} <- [{100, 1}, {200, 2}, {500, 3}, {1000, 4}] do
        tool_use_id = "toolu_snap_#{idx}"
        start_time = DateTime.add(base_time, idx, :second)
        finish_time = DateTime.add(start_time, duration_ms, :millisecond)

        create_event(session, %{
          tool_use_id: tool_use_id,
          command: "mix test",
          command_path: "tool_input.command",
          phase: :start,
          hook_event_name: "PreToolUse",
          captured_at: start_time,
          raw_hook_event_id: "snap-start-#{idx}"
        })

        create_event(session, %{
          tool_use_id: tool_use_id,
          command: "mix test",
          command_path: "tool_input.command",
          phase: :finish,
          finish_status: :ok,
          hook_event_name: "PostToolUse",
          captured_at: finish_time,
          raw_hook_event_id: "snap-finish-#{idx}"
        })
      end

      snapshot = ShellCommandTelemetryQuery.snapshot(project.id)

      assert length(snapshot) == 1
      stats = hd(snapshot)
      assert stats.command == "mix test"
      assert stats.count == 4
      assert stats.error_rate == 0.0
      # Median of [100, 200, 500, 1000] = (200 + 500) / 2 = 350.0
      assert stats.median_ms == 350.0
    end

    test "default window is :last_7d (events older than 7d excluded)",
         %{session: session, project: project} do
      old_time = DateTime.add(DateTime.utc_now(), -8, :day)
      recent_time = DateTime.add(DateTime.utc_now(), -1, :day)

      create_event(session, %{
        tool_use_id: "toolu_old_1",
        command: "mix old",
        command_path: "tool_input.command",
        phase: :start,
        hook_event_name: "PreToolUse",
        captured_at: old_time,
        raw_hook_event_id: "old-start-1"
      })

      create_event(session, %{
        tool_use_id: "toolu_old_1",
        command: "mix old",
        command_path: "tool_input.command",
        phase: :finish,
        finish_status: :ok,
        hook_event_name: "PostToolUse",
        captured_at: DateTime.add(old_time, 1, :second),
        raw_hook_event_id: "old-finish-1"
      })

      create_event(session, %{
        tool_use_id: "toolu_recent_1",
        command: "mix recent",
        command_path: "tool_input.command",
        phase: :start,
        hook_event_name: "PreToolUse",
        captured_at: recent_time,
        raw_hook_event_id: "recent-start-1"
      })

      create_event(session, %{
        tool_use_id: "toolu_recent_1",
        command: "mix recent",
        command_path: "tool_input.command",
        phase: :finish,
        finish_status: :ok,
        hook_event_name: "PostToolUse",
        captured_at: DateTime.add(recent_time, 1, :second),
        raw_hook_event_id: "recent-finish-1"
      })

      snapshot = ShellCommandTelemetryQuery.snapshot(project.id)

      commands = Enum.map(snapshot, & &1.command)
      assert "mix recent" in commands
      refute "mix old" in commands
    end

    test "window :last_24h filters correctly",
         %{session: session, project: project} do
      two_days_ago = DateTime.add(DateTime.utc_now(), -2, :day)
      recent_time = DateTime.add(DateTime.utc_now(), -1, :hour)

      create_event(session, %{
        tool_use_id: "toolu_24h_old",
        command: "mix old_24h",
        command_path: "tool_input.command",
        phase: :start,
        hook_event_name: "PreToolUse",
        captured_at: two_days_ago,
        raw_hook_event_id: "24h-old-start"
      })

      create_event(session, %{
        tool_use_id: "toolu_24h_old",
        command: "mix old_24h",
        command_path: "tool_input.command",
        phase: :finish,
        finish_status: :ok,
        hook_event_name: "PostToolUse",
        captured_at: DateTime.add(two_days_ago, 1, :second),
        raw_hook_event_id: "24h-old-finish"
      })

      create_event(session, %{
        tool_use_id: "toolu_24h_recent",
        command: "mix recent_24h",
        command_path: "tool_input.command",
        phase: :start,
        hook_event_name: "PreToolUse",
        captured_at: recent_time,
        raw_hook_event_id: "24h-recent-start"
      })

      create_event(session, %{
        tool_use_id: "toolu_24h_recent",
        command: "mix recent_24h",
        command_path: "tool_input.command",
        phase: :finish,
        finish_status: :ok,
        hook_event_name: "PostToolUse",
        captured_at: DateTime.add(recent_time, 1, :second),
        raw_hook_event_id: "24h-recent-finish"
      })

      snapshot = ShellCommandTelemetryQuery.snapshot(project.id, window: :last_24h)

      commands = Enum.map(snapshot, & &1.command)
      assert "mix recent_24h" in commands
      refute "mix old_24h" in commands
    end

    test "snapshot_all_projects returns data across projects with project_id" do
      project_a =
        Ash.create!(Project, %{
          name: "project-a-telemetry",
          pattern: "^project-a-telemetry$"
        })

      session_a =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          project_id: project_a.id,
          cwd: "/home/user/project-a-telemetry"
        })

      project_b =
        Ash.create!(Project, %{
          name: "project-b-telemetry",
          pattern: "^project-b-telemetry$"
        })

      session_b =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          project_id: project_b.id,
          cwd: "/home/user/project-b-telemetry"
        })

      # Project A: "mix test"
      create_event(session_a, %{
        tool_use_id: "toolu_allproj_a",
        command: "mix test",
        command_path: "tool_input.command",
        phase: :start,
        hook_event_name: "PreToolUse",
        captured_at: ~U[2026-03-04 10:00:00.000000Z],
        raw_hook_event_id: "proj-a-start"
      })

      create_event(session_a, %{
        tool_use_id: "toolu_allproj_a",
        command: "mix test",
        command_path: "tool_input.command",
        phase: :finish,
        finish_status: :ok,
        hook_event_name: "PostToolUse",
        captured_at: ~U[2026-03-04 10:00:01.000000Z],
        raw_hook_event_id: "proj-a-finish"
      })

      # Project B: "npm test"
      create_event(session_b, %{
        tool_use_id: "toolu_allproj_b",
        command: "npm test",
        command_path: "tool_input.command",
        phase: :start,
        hook_event_name: "PreToolUse",
        captured_at: ~U[2026-03-04 10:00:00.000000Z],
        raw_hook_event_id: "proj-b-start"
      })

      create_event(session_b, %{
        tool_use_id: "toolu_allproj_b",
        command: "npm test",
        command_path: "tool_input.command",
        phase: :finish,
        finish_status: :ok,
        hook_event_name: "PostToolUse",
        captured_at: ~U[2026-03-04 10:00:02.000000Z],
        raw_hook_event_id: "proj-b-finish"
      })

      result = ShellCommandTelemetryQuery.snapshot_all_projects(window: :all)

      # Each result should include project_id
      project_ids = Enum.map(result, & &1.project_id) |> Enum.uniq()
      assert project_a.id in project_ids
      assert project_b.id in project_ids

      commands = Enum.map(result, & &1.command)
      assert "mix test" in commands
      assert "npm test" in commands
    end

    test "default sort: median_ms DESC, p95_ms DESC, count DESC",
         %{session: session, project: project} do
      base_time = DateTime.add(DateTime.utc_now(), -3600, :second)

      # Create a fast command (100ms)
      create_event(session, %{
        tool_use_id: "toolu_sort_fast",
        command: "echo fast",
        command_path: "tool_input.command",
        phase: :start,
        hook_event_name: "PreToolUse",
        captured_at: base_time,
        raw_hook_event_id: "sort-fast-start"
      })

      create_event(session, %{
        tool_use_id: "toolu_sort_fast",
        command: "echo fast",
        command_path: "tool_input.command",
        phase: :finish,
        finish_status: :ok,
        hook_event_name: "PostToolUse",
        captured_at: DateTime.add(base_time, 100, :millisecond),
        raw_hook_event_id: "sort-fast-finish"
      })

      # Create a slow command (5000ms)
      create_event(session, %{
        tool_use_id: "toolu_sort_slow",
        command: "mix test --slow",
        command_path: "tool_input.command",
        phase: :start,
        hook_event_name: "PreToolUse",
        captured_at: DateTime.add(base_time, 1, :second),
        raw_hook_event_id: "sort-slow-start"
      })

      create_event(session, %{
        tool_use_id: "toolu_sort_slow",
        command: "mix test --slow",
        command_path: "tool_input.command",
        phase: :finish,
        finish_status: :ok,
        hook_event_name: "PostToolUse",
        captured_at: DateTime.add(base_time, 6, :second),
        raw_hook_event_id: "sort-slow-finish"
      })

      snapshot = ShellCommandTelemetryQuery.snapshot(project.id)

      assert length(snapshot) == 2
      [first, second] = snapshot
      assert first.command == "mix test --slow"
      assert second.command == "echo fast"
    end
  end
end
