defmodule Spotter.Transcripts.ToolCallRunTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Project, Session, ToolCallRun}

  setup do
    Sandbox.checkout(Spotter.Repo)

    project =
      Ash.create!(Project, %{name: "tcr-test", pattern: "^tcr-test$"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

    %{project: project, session: session}
  end

  describe "create" do
    test "creates a tool call run with all required fields", %{session: session, project: project} do
      run =
        Ash.create!(ToolCallRun, %{
          tool_use_id: "toolu_abc123",
          tool_name: "Bash",
          command: "mix test",
          session_id: session.id,
          project_id: project.id,
          started_at: ~U[2026-03-20 10:00:00Z],
          finished_at: ~U[2026-03-20 10:00:02.500Z],
          duration_ms: 2500,
          status: :completed,
          command_fingerprint: "mix test"
        })

      assert run.tool_use_id == "toolu_abc123"
      assert run.tool_name == "Bash"
      assert run.command == "mix test"
      assert run.duration_ms == 2500
      assert run.status == :completed
      assert run.command_fingerprint == "mix test"
    end

    test "requires tool_use_id, tool_name, session_id, project_id", %{
      session: session,
      project: project
    } do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(ToolCallRun, %{
          command: "mix test",
          session_id: session.id,
          project_id: project.id
        })
      end
    end
  end

  describe "duration derivation" do
    test "explicit duration_ms is stored as-is", %{session: session, project: project} do
      run =
        Ash.create!(ToolCallRun, %{
          tool_use_id: "toolu_dur_explicit",
          tool_name: "Bash",
          command: "mix test",
          session_id: session.id,
          project_id: project.id,
          started_at: ~U[2026-03-20 10:00:00Z],
          finished_at: ~U[2026-03-20 10:00:05Z],
          duration_ms: 2500,
          status: :completed
        })

      assert run.duration_ms == 2500
    end

    test "duration derived from timestamps when not explicitly provided", %{
      session: session,
      project: project
    } do
      run =
        Ash.create!(ToolCallRun, %{
          tool_use_id: "toolu_dur_derived",
          tool_name: "Bash",
          command: "mix test",
          session_id: session.id,
          project_id: project.id,
          started_at: ~U[2026-03-20 10:00:00Z],
          finished_at: ~U[2026-03-20 10:00:03Z],
          status: :completed
        })

      assert run.duration_ms == 3000
    end

    test "ongoing status when no finished_at", %{session: session, project: project} do
      run =
        Ash.create!(ToolCallRun, %{
          tool_use_id: "toolu_dur_ongoing",
          tool_name: "Bash",
          command: "mix test",
          session_id: session.id,
          project_id: project.id,
          started_at: ~U[2026-03-20 10:00:00Z],
          status: :ongoing
        })

      assert run.status == :ongoing
      assert run.finished_at == nil
      assert run.duration_ms == nil
    end

    test "orphan status when no started_at (finish-only event)", %{
      session: session,
      project: project
    } do
      run =
        Ash.create!(ToolCallRun, %{
          tool_use_id: "toolu_dur_orphan",
          tool_name: "Bash",
          command: "mix test",
          session_id: session.id,
          project_id: project.id,
          finished_at: ~U[2026-03-20 10:00:05Z],
          status: :orphan
        })

      assert run.status == :orphan
      assert run.started_at == nil
      assert run.duration_ms == nil
    end
  end

  describe "command fingerprint normalization" do
    test "normalizes whitespace in fingerprint", %{session: session, project: project} do
      run =
        Ash.create!(ToolCallRun, %{
          tool_use_id: "toolu_fp_ws",
          tool_name: "Bash",
          command: "mix  test   --trace",
          session_id: session.id,
          project_id: project.id,
          started_at: ~U[2026-03-20 10:00:00Z],
          status: :ongoing,
          command_fingerprint: "mix test --trace"
        })

      assert run.command_fingerprint == "mix test --trace"
    end

    test "normalizes paths in fingerprint", %{session: session, project: project} do
      run =
        Ash.create!(ToolCallRun, %{
          tool_use_id: "toolu_fp_path",
          tool_name: "Bash",
          command: "cat /home/user/project/lib/foo.ex",
          session_id: session.id,
          project_id: project.id,
          started_at: ~U[2026-03-20 10:00:00Z],
          status: :ongoing,
          command_fingerprint: "cat <PATH>"
        })

      assert run.command_fingerprint == "cat <PATH>"
    end
  end

  describe "upsert by tool_use_id" do
    test "upsert is idempotent — second create with same tool_use_id updates fields", %{
      session: session,
      project: project
    } do
      attrs = %{
        tool_use_id: "toolu_upsert_1",
        tool_name: "Bash",
        command: "mix test",
        session_id: session.id,
        project_id: project.id,
        started_at: ~U[2026-03-20 10:00:00Z],
        status: :ongoing
      }

      first = Ash.create!(ToolCallRun, attrs, action: :upsert)

      second =
        Ash.create!(
          ToolCallRun,
          Map.merge(attrs, %{
            finished_at: ~U[2026-03-20 10:00:02Z],
            duration_ms: 2000,
            status: :completed
          }),
          action: :upsert
        )

      assert first.id == second.id
      assert second.status == :completed
      assert second.duration_ms == 2000
    end
  end
end
