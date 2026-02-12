defmodule Spotter.Transcripts.Jobs.SyncTranscriptsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{JsonlParser, Project, Session, SessionRework}

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "test-sync", pattern: "^test"})
    session_id = Ash.UUID.generate()

    session =
      Ash.create!(Session, %{
        session_id: session_id,
        transcript_dir: "test-dir",
        cwd: "/home/user/project",
        project_id: project.id
      })

    %{session: session}
  end

  describe "rework persistence via extract + upsert" do
    test "persists rework records for repeated file modifications", %{session: session} do
      messages = build_rework_messages()

      rework_records =
        JsonlParser.extract_session_rework_records(messages,
          session_cwd: "/home/user/project"
        )

      assert length(rework_records) == 2

      Enum.each(rework_records, fn record ->
        Ash.create!(SessionRework, Map.put(record, :session_id, session.id), action: :upsert)
      end)

      persisted =
        SessionRework
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.Query.sort(occurrence_index: :asc)
        |> Ash.read!()

      assert length(persisted) == 2
      assert Enum.at(persisted, 0).occurrence_index == 2
      assert Enum.at(persisted, 1).occurrence_index == 3
      assert Enum.at(persisted, 0).relative_path == "lib/foo.ex"
    end

    test "rerunning sync does not duplicate records (idempotent)", %{session: session} do
      messages = build_rework_messages()

      persist_rework!(session, messages)
      persist_rework!(session, messages)

      persisted =
        SessionRework
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.read!()

      assert length(persisted) == 2
    end

    test "failed tool results do not produce rework records", %{session: session} do
      messages = [
        assistant_write("tu-1", "/home/user/project/lib/foo.ex"),
        tool_result("tu-1", false),
        assistant_edit("tu-2", "/home/user/project/lib/foo.ex"),
        tool_result("tu-2", true),
        assistant_edit("tu-3", "/home/user/project/lib/foo.ex"),
        tool_result("tu-3", false)
      ]

      persist_rework!(session, messages)

      persisted =
        SessionRework
        |> Ash.Query.filter(session_id == ^session.id)
        |> Ash.read!()

      # tu-1 is first success, tu-2 failed (ignored), tu-3 is second success -> 1 rework
      assert length(persisted) == 1
      assert hd(persisted).tool_use_id == "tu-3"
      assert hd(persisted).occurrence_index == 2
    end
  end

  defp persist_rework!(session, messages) do
    rework_records =
      JsonlParser.extract_session_rework_records(messages,
        session_cwd: session.cwd
      )

    Enum.each(rework_records, fn record ->
      Ash.create!(SessionRework, Map.put(record, :session_id, session.id), action: :upsert)
    end)
  end

  defp build_rework_messages do
    [
      assistant_write("tu-1", "/home/user/project/lib/foo.ex"),
      tool_result("tu-1", false),
      assistant_edit("tu-2", "/home/user/project/lib/foo.ex"),
      tool_result("tu-2", false),
      assistant_edit("tu-3", "/home/user/project/lib/foo.ex"),
      tool_result("tu-3", false)
    ]
  end

  defp assistant_write(tool_use_id, file_path) do
    %{
      uuid: "msg-#{tool_use_id}",
      type: :assistant,
      role: :assistant,
      timestamp: ~U[2026-02-12 10:00:00Z],
      content: %{
        "blocks" => [
          %{
            "type" => "tool_use",
            "id" => tool_use_id,
            "name" => "Write",
            "input" => %{"file_path" => file_path}
          }
        ]
      }
    }
  end

  defp assistant_edit(tool_use_id, file_path) do
    %{
      uuid: "msg-#{tool_use_id}",
      type: :assistant,
      role: :assistant,
      timestamp: ~U[2026-02-12 10:01:00Z],
      content: %{
        "blocks" => [
          %{
            "type" => "tool_use",
            "id" => tool_use_id,
            "name" => "Edit",
            "input" => %{"file_path" => file_path}
          }
        ]
      }
    }
  end

  defp tool_result(tool_use_id, is_error) do
    %{
      uuid: "result-#{tool_use_id}",
      type: :tool_result,
      role: :user,
      timestamp: ~U[2026-02-12 10:00:01Z],
      content: %{
        "blocks" => [
          %{
            "type" => "tool_result",
            "tool_use_id" => tool_use_id,
            "is_error" => is_error,
            "content" => if(is_error, do: "Error", else: "OK")
          }
        ]
      }
    }
  end
end
