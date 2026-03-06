defmodule Spotter.Services.InstructionsTelemetryQueryTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Services.InstructionsTelemetryQuery
  alias Spotter.Transcripts.{InstructionsLoadedEvent, Project, Session}

  require Ash.Query

  setup do
    Sandbox.checkout(Spotter.Repo)

    project = Ash.create!(Project, %{name: "query-test", pattern: "^query-test$"})
    session_id = Ash.UUID.generate()

    session =
      Ash.create!(Session, %{
        session_id: session_id,
        project_id: project.id,
        cwd: "/home/user/query-test"
      })

    %{project: project, session: session, session_id: session_id}
  end

  defp create_event(attrs) do
    defaults = %{
      raw_hook_event_id: Ash.UUID.generate(),
      file_path: "/default/path.md",
      captured_at: DateTime.utc_now(),
      bytes_loaded: 100,
      lines_loaded: 10,
      size_status: "ok"
    }

    Ash.create!(InstructionsLoadedEvent, Map.merge(defaults, attrs))
  end

  test "returns summary with correct counts", %{
    project: project,
    session: session,
    session_id: session_id
  } do
    create_event(%{
      project_id: project.id,
      session_id: session.id,
      external_session_id: session_id,
      file_path: "/a.md"
    })

    create_event(%{
      project_id: project.id,
      session_id: session.id,
      external_session_id: session_id,
      file_path: "/b.md",
      bytes_loaded: 200,
      lines_loaded: 20
    })

    result = InstructionsTelemetryQuery.query(project.id, window: :all)

    assert result.summary.total_loads == 2
    assert result.summary.unique_documents == 2
    assert result.summary.unique_sessions == 1
    assert result.summary.total_bytes == 300
    assert result.summary.total_lines == 30
  end

  test "returns document rows sorted by load_count", %{
    project: project,
    session: session,
    session_id: session_id
  } do
    create_event(%{
      project_id: project.id,
      session_id: session.id,
      external_session_id: session_id,
      file_path: "/frequent.md"
    })

    create_event(%{
      project_id: project.id,
      session_id: session.id,
      external_session_id: session_id,
      file_path: "/frequent.md"
    })

    create_event(%{
      project_id: project.id,
      session_id: session.id,
      external_session_id: session_id,
      file_path: "/rare.md"
    })

    result = InstructionsTelemetryQuery.query(project.id, window: :all)

    assert length(result.documents) == 2
    [first | _] = result.documents
    assert first.file_path == "/frequent.md"
    assert first.load_count == 2
  end

  test "empty result for project with no events", %{project: _project} do
    other = Ash.create!(Project, %{name: "empty-proj", pattern: "^empty-proj$"})

    result = InstructionsTelemetryQuery.query(other.id, window: :all)

    assert result.summary.total_loads == 0
    assert result.documents == []
    assert result.sessions == []
  end
end
