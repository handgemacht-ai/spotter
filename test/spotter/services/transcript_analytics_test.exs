defmodule Spotter.Services.TranscriptAnalyticsTest do
  use ExUnit.Case, async: false

  require Ash.Query

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
      _run = create_run(session, project, %{tool_use_id: "i-detail-1"})

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

  describe "search/1 error_contains filter" do
    test "filters by error_content text", %{project: project, session: session} do
      create_run(session, project, %{
        tool_use_id: "ec-1",
        status: :error,
        error_content: "File has not been read yet"
      })

      create_run(session, project, %{
        tool_use_id: "ec-2",
        status: :error,
        error_content: "Exit code 1"
      })

      {:ok, results} =
        TranscriptAnalytics.search(%{
          project_id: project.id,
          error_contains: "not been read"
        })

      assert length(results) == 1
      assert hd(results).tool_use_id == "ec-1"
    end
  end

  describe "classify_error/1" do
    test "classifies user rejection" do
      assert :user_rejected ==
               TranscriptAnalytics.classify_error(
                 "The user doesn't want to proceed with this tool use."
               )
    end

    test "classifies sibling errors" do
      assert :sibling_errored ==
               TranscriptAnalytics.classify_error(
                 "<tool_use_error>Sibling tool call errored</tool_use_error>"
               )
    end

    test "classifies hook blocked" do
      assert :hook_blocked ==
               TranscriptAnalytics.classify_error(
                 "PreToolUse:Bash hook error: BLOCKED: Do not manipulate"
               )

      assert :hook_blocked ==
               TranscriptAnalytics.classify_error("Hook PreToolUse:Bash denied this tool")
    end

    test "classifies file not read first" do
      assert :file_not_read_first ==
               TranscriptAnalytics.classify_error(
                 "<tool_use_error>File has not been read yet.</tool_use_error>"
               )
    end

    test "classifies file modified since read" do
      assert :file_modified_since_read ==
               TranscriptAnalytics.classify_error(
                 "File has been modified since read, either by the user or by a linter."
               )
    end

    test "classifies file not found" do
      assert :file_not_found ==
               TranscriptAnalytics.classify_error("File does not exist. Note: your cwd is /foo")

      assert :file_not_found ==
               TranscriptAnalytics.classify_error("No such file or directory")
    end

    test "classifies token limit exceeded" do
      assert :token_limit_exceeded ==
               TranscriptAnalytics.classify_error(
                 "File content (11243 tokens) exceeds maximum allowed tokens (10000)."
               )
    end

    test "classifies MCP errors" do
      assert :mcp_error ==
               TranscriptAnalytics.classify_error("MCP error -32000: Tool execution failed")
    end

    test "classifies pre-commit failures" do
      assert :pre_commit_failed ==
               TranscriptAnalytics.classify_error(
                 "Precommit failed:\n\nNo vulnerabilities found."
               )
    end

    test "classifies exit code errors" do
      assert :exit_code == TranscriptAnalytics.classify_error("Exit code 1")
    end

    test "classifies nil and empty as other" do
      assert :other == TranscriptAnalytics.classify_error(nil)
      assert :other == TranscriptAnalytics.classify_error("")
    end

    test "classifies unknown errors as other" do
      assert :other == TranscriptAnalytics.classify_error("Something unexpected happened")
    end
  end

  describe "error_preventability/1" do
    test "preventable categories" do
      for cat <- [
            :file_not_read_first,
            :file_modified_since_read,
            :file_not_found,
            :path_error,
            :token_limit_exceeded
          ] do
        assert :preventable == TranscriptAnalytics.error_preventability(cat)
      end
    end

    test "user-driven categories" do
      for cat <- [:user_rejected, :hook_blocked] do
        assert :user_driven == TranscriptAnalytics.error_preventability(cat)
      end
    end

    test "systemic categories" do
      for cat <- [:exit_code, :mcp_error, :pre_commit_failed] do
        assert :systemic == TranscriptAnalytics.error_preventability(cat)
      end
    end

    test "cascading category" do
      assert :cascading == TranscriptAnalytics.error_preventability(:sibling_errored)
    end
  end

  describe "error_analysis/1 with classify" do
    test "adds classification fields when classify is true", %{
      project: project,
      session: session
    } do
      create_run(session, project, %{
        tool_use_id: "ea-c-1",
        tool_name: "Edit",
        status: :error,
        error_content: "File has not been read yet."
      })

      create_run(session, project, %{tool_use_id: "ea-c-ok", tool_name: "Edit"})

      results = TranscriptAnalytics.error_analysis(%{project_id: project.id, classify: true})

      assert [pattern] = results
      assert pattern.category == :file_not_read_first
      assert pattern.preventability == :preventable
      assert pattern.total_tool_calls == 2
      assert pattern.error_rate > 0
    end

    test "omits classification fields without classify flag", %{
      project: project,
      session: session
    } do
      create_run(session, project, %{
        tool_use_id: "ea-nc-1",
        status: :error,
        error_content: "Exit code 1"
      })

      results = TranscriptAnalytics.error_analysis(%{project_id: project.id})
      assert [pattern] = results
      refute Map.has_key?(pattern, :category)
    end
  end

  describe "inspect/1 with status_filter" do
    test "filters runs by status", %{project: project, session: session} do
      create_run(session, project, %{
        tool_use_id: "if-1",
        status: :completed,
        start_ordinal: 1
      })

      create_run(session, project, %{
        tool_use_id: "if-2",
        status: :error,
        error_content: "Exit code 1",
        start_ordinal: 2
      })

      create_run(session, project, %{
        tool_use_id: "if-3",
        status: :completed,
        start_ordinal: 3
      })

      {:ok, results} =
        TranscriptAnalytics.inspect(%{session_id: session.id, status_filter: :error})

      assert length(results) == 1
      assert hd(results).tool_use_id == "if-2"
    end

    test "status filter with context includes surrounding runs", %{
      project: project,
      session: session
    } do
      for i <- 1..5 do
        status = if i == 3, do: :error, else: :completed

        create_run(session, project, %{
          tool_use_id: "ifc-#{i}",
          status: status,
          error_content: if(i == 3, do: "Exit code 1"),
          start_ordinal: i
        })
      end

      {:ok, results} =
        TranscriptAnalytics.inspect(%{
          session_id: session.id,
          status_filter: :error,
          context: 1
        })

      assert length(results) == 3
      tool_use_ids = Enum.map(results, & &1.tool_use_id)
      assert "ifc-2" in tool_use_ids
      assert "ifc-3" in tool_use_ids
      assert "ifc-4" in tool_use_ids
    end
  end

  describe "sequence_analysis/1 with recovery" do
    test "returns recovery stats when recovery flag is set", %{
      project: project,
      session: session
    } do
      create_run(session, project, %{
        tool_use_id: "sr-1",
        tool_name: "Edit",
        status: :error,
        error_content: "File has not been read yet.",
        start_ordinal: 1
      })

      create_run(session, project, %{
        tool_use_id: "sr-2",
        tool_name: "Edit",
        status: :completed,
        start_ordinal: 2
      })

      result =
        TranscriptAnalytics.sequence_analysis(%{
          project_id: project.id,
          recovery: true,
          min_occurrences: 1
        })

      assert is_list(result.recovery_stats)
      assert result.recovery_stats != []

      file_not_read = Enum.find(result.recovery_stats, &(&1.category == :file_not_read_first))
      assert file_not_read
      assert file_not_read.total_errors == 1
      assert file_not_read.retry_rate > 0
      assert file_not_read.recovery_rate > 0
    end

    test "omits recovery stats without flag", %{project: project} do
      result = TranscriptAnalytics.sequence_analysis(%{project_id: project.id})
      refute Map.has_key?(result, :recovery_stats)
    end
  end

  describe "tool_input extraction" do
    test "stores skill name in tool_input", %{session: session, project: project} do
      run =
        create_run(session, project, %{
          tool_name: "Skill",
          command: nil,
          command_fingerprint: nil,
          tool_input: %{"skill" => "ash-framework", "args" => "-v"}
        })

      assert run.tool_input == %{"skill" => "ash-framework", "args" => "-v"}
    end

    test "stores file_path in tool_input for Read", %{session: session, project: project} do
      run =
        create_run(session, project, %{
          tool_name: "Read",
          command: nil,
          command_fingerprint: nil,
          tool_input: %{"file_path" => "/srv/project/lib/foo.ex"}
        })

      assert run.tool_input["file_path"] == "/srv/project/lib/foo.ex"
    end

    test "tool_input can be nil", %{session: session, project: project} do
      run =
        create_run(session, project, %{
          tool_name: "Bash",
          tool_input: nil
        })

      assert run.tool_input == nil
    end

    test "skill runs are filterable via tool_input", %{session: session, project: project} do
      create_run(session, project, %{
        tool_name: "Skill",
        command: nil,
        command_fingerprint: nil,
        tool_input: %{"skill" => "ash-framework"}
      })

      create_run(session, project, %{
        tool_name: "Skill",
        command: nil,
        command_fingerprint: nil,
        tool_input: %{"skill" => "commit"}
      })

      create_run(session, project, %{
        tool_name: "Bash",
        tool_input: nil
      })

      all_skills =
        ToolCallRun
        |> Ash.Query.filter(tool_name == "Skill")
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.read!()

      assert length(all_skills) == 2
    end
  end
end
