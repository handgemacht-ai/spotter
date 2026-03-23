defmodule Spotter.Services.TranscriptAnalyticsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Services.TranscriptAnalytics
  alias Spotter.Transcripts.{Project, Session, ToolCallRun}

  setup do
    Sandbox.checkout(Spotter.Repo)

    project =
      Ash.create!(Project, %{name: "analytics-test", pattern: "^analytics-test$"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "analytics-dir",
        project_id: project.id,
        ingest_status: :complete
      })

    session_b =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "analytics-dir-b",
        project_id: project.id,
        ingest_status: :partial
      })

    %{project: project, session: session, session_b: session_b}
  end

  defp create_run(session, project, attrs) do
    defaults = %{
      tool_use_id: Ash.UUID.generate(),
      tool_name: "Bash",
      command: "mix test",
      session_id: session.id,
      project_id: project.id,
      started_at: ~U[2026-03-20 10:00:00Z],
      finished_at: ~U[2026-03-20 10:00:02Z],
      duration_ms: 2000,
      status: :completed,
      command_fingerprint: "mix test"
    }

    Ash.create!(ToolCallRun, Map.merge(defaults, attrs))
  end

  describe "search/1" do
    test "filters by project_id", %{project: project, session: session} do
      create_run(session, project, %{tool_use_id: "s-proj-1"})

      other_project =
        Ash.create!(Project, %{name: "other-project", pattern: "^other-project$"})

      other_session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "other-dir",
          project_id: other_project.id
        })

      create_run(other_session, other_project, %{tool_use_id: "s-proj-2"})

      {:ok, results} = TranscriptAnalytics.search(%{project_id: project.id})
      assert length(results) == 1
      assert hd(results).tool_use_id == "s-proj-1"
    end

    test "filters by session_id", %{project: project, session: session, session_b: session_b} do
      create_run(session, project, %{tool_use_id: "s-sess-1"})
      create_run(session_b, project, %{tool_use_id: "s-sess-2"})

      {:ok, results} = TranscriptAnalytics.search(%{session_id: session.id})
      assert length(results) == 1
      assert hd(results).tool_use_id == "s-sess-1"
    end

    test "filters by tool name", %{project: project, session: session} do
      create_run(session, project, %{tool_use_id: "s-tool-1", tool_name: "Bash"})
      create_run(session, project, %{tool_use_id: "s-tool-2", tool_name: "Read"})

      {:ok, results} = TranscriptAnalytics.search(%{project_id: project.id, tool: "Bash"})
      assert length(results) == 1
      assert hd(results).tool_name == "Bash"
    end

    test "filters by command_contains", %{project: project, session: session} do
      create_run(session, project, %{tool_use_id: "s-cmd-1", command: "mix test --trace"})
      create_run(session, project, %{tool_use_id: "s-cmd-2", command: "git status"})

      {:ok, results} =
        TranscriptAnalytics.search(%{project_id: project.id, command_contains: "mix"})

      assert length(results) == 1
      assert hd(results).command =~ "mix"
    end

    test "filters by min_duration_ms", %{project: project, session: session} do
      create_run(session, project, %{tool_use_id: "s-dur-1", duration_ms: 100})
      create_run(session, project, %{tool_use_id: "s-dur-2", duration_ms: 5000})

      {:ok, results} =
        TranscriptAnalytics.search(%{project_id: project.id, min_duration_ms: 1000})

      assert length(results) == 1
      assert hd(results).duration_ms == 5000
    end

    test "filters by max_duration_ms", %{project: project, session: session} do
      create_run(session, project, %{tool_use_id: "s-maxd-1", duration_ms: 100})
      create_run(session, project, %{tool_use_id: "s-maxd-2", duration_ms: 5000})

      {:ok, results} =
        TranscriptAnalytics.search(%{project_id: project.id, max_duration_ms: 1000})

      assert length(results) == 1
      assert hd(results).duration_ms == 100
    end

    test "filters by status", %{project: project, session: session} do
      create_run(session, project, %{tool_use_id: "s-stat-1", status: :completed})

      create_run(session, project, %{
        tool_use_id: "s-stat-2",
        status: :ongoing,
        finished_at: nil,
        duration_ms: nil
      })

      {:ok, results} =
        TranscriptAnalytics.search(%{project_id: project.id, status: :ongoing})

      assert length(results) == 1
      assert hd(results).status == :ongoing
    end

    test "respects limit option", %{project: project, session: session} do
      for i <- 1..5 do
        create_run(session, project, %{tool_use_id: "s-limit-#{i}"})
      end

      {:ok, results} = TranscriptAnalytics.search(%{project_id: project.id, limit: 3})
      assert length(results) == 3
    end

    test "exposes session ingest_status in results", %{project: project, session: session} do
      create_run(session, project, %{tool_use_id: "s-ingest-1"})

      {:ok, results} = TranscriptAnalytics.search(%{project_id: project.id})
      result = hd(results)
      assert result.ingest_status == :complete
    end

    test "runs with no finish event surface as ongoing status", %{
      project: project,
      session: session
    } do
      create_run(session, project, %{
        tool_use_id: "s-ongoing-1",
        status: :ongoing,
        finished_at: nil,
        duration_ms: nil
      })

      {:ok, results} =
        TranscriptAnalytics.search(%{project_id: project.id, status: :ongoing})

      assert length(results) == 1
      assert hd(results).status == :ongoing
    end

    test "runs with orphan status are searchable", %{project: project, session: session} do
      create_run(session, project, %{
        tool_use_id: "s-orphan-1",
        status: :orphan,
        started_at: nil,
        duration_ms: nil
      })

      {:ok, results} =
        TranscriptAnalytics.search(%{project_id: project.id, status: :orphan})

      assert length(results) == 1
      assert hd(results).status == :orphan
    end
  end

  describe "inspect/1" do
    test "returns tool call run detail for a session", %{project: project, session: session} do
      run = create_run(session, project, %{tool_use_id: "i-detail-1"})

      {:ok, result} =
        TranscriptAnalytics.inspect(%{session_id: session.id})

      assert is_list(result)
      assert Enum.any?(result, fn r -> r.tool_use_id == "i-detail-1" end)
    end

    test "filters by tool_use_id within session", %{project: project, session: session} do
      create_run(session, project, %{tool_use_id: "i-specific-1"})
      create_run(session, project, %{tool_use_id: "i-specific-2"})

      {:ok, result} =
        TranscriptAnalytics.inspect(%{
          session_id: session.id,
          tool_use_id: "i-specific-1"
        })

      assert length(result) == 1
      assert hd(result).tool_use_id == "i-specific-1"
    end

    test "supports context lines option", %{project: project, session: session} do
      create_run(session, project, %{tool_use_id: "i-ctx-1"})

      {:ok, result} =
        TranscriptAnalytics.inspect(%{
          session_id: session.id,
          tool_use_id: "i-ctx-1",
          context: 3
        })

      assert is_list(result)
    end
  end

  describe "compare/1" do
    test "compares tool runs between two session cohorts", %{
      project: project,
      session: session,
      session_b: session_b
    } do
      create_run(session, project, %{
        tool_use_id: "c-left-1",
        duration_ms: 1000,
        command_fingerprint: "mix test"
      })

      create_run(session_b, project, %{
        tool_use_id: "c-right-1",
        duration_ms: 3000,
        command_fingerprint: "mix test"
      })

      {:ok, result} =
        TranscriptAnalytics.compare(%{
          left_sessions: [session.id],
          right_sessions: [session_b.id]
        })

      assert is_map(result)
      assert Map.has_key?(result, :left)
      assert Map.has_key?(result, :right)
    end

    test "filters comparison by tool", %{
      project: project,
      session: session,
      session_b: session_b
    } do
      create_run(session, project, %{tool_use_id: "c-tf-1", tool_name: "Bash"})
      create_run(session, project, %{tool_use_id: "c-tf-2", tool_name: "Read"})
      create_run(session_b, project, %{tool_use_id: "c-tf-3", tool_name: "Bash"})

      {:ok, result} =
        TranscriptAnalytics.compare(%{
          left_sessions: [session.id],
          right_sessions: [session_b.id],
          tool: "Bash"
        })

      assert is_map(result)
    end

    test "supports group_by option", %{
      project: project,
      session: session,
      session_b: session_b
    } do
      create_run(session, project, %{tool_use_id: "c-gb-1"})
      create_run(session_b, project, %{tool_use_id: "c-gb-2"})

      {:ok, result} =
        TranscriptAnalytics.compare(%{
          left_sessions: [session.id],
          right_sessions: [session_b.id],
          group_by: :command_fingerprint
        })

      assert is_map(result)
    end

    test "returns error tuple with empty left cohort", %{session: session} do
      assert {:error, _reason} =
               TranscriptAnalytics.compare(%{
                 left_sessions: [],
                 right_sessions: [session.id]
               })
    end

    test "returns error tuple with empty right cohort", %{session: session} do
      assert {:error, _reason} =
               TranscriptAnalytics.compare(%{
                 left_sessions: [session.id],
                 right_sessions: []
               })
    end
  end
end
