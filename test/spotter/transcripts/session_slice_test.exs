defmodule Spotter.Transcripts.SessionSliceTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Project, Session, SessionSlice}

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    project = Ash.create!(Project, %{name: "slice-test", pattern: "^slice"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        cwd: "/tmp/test",
        project_id: project.id
      })

    %{project: project, session: session}
  end

  describe "create" do
    test "creates a session slice with all fields", %{session: session, project: project} do
      assert {:ok, slice} =
               Ash.create(SessionSlice, %{
                 session_id: session.id,
                 project_id: project.id,
                 title: "Test slice",
                 filters: %{"tool" => "Bash"},
                 highlight_tool_use_ids: ["toolu_abc", "toolu_def"],
                 context_before_lines: 5,
                 context_after_lines: 5
               })

      assert slice.title == "Test slice"
      assert slice.session_id == session.id
      assert slice.highlight_tool_use_ids == ["toolu_abc", "toolu_def"]
      assert slice.context_before_lines == 5
      assert slice.context_after_lines == 5
      assert slice.inserted_at != nil
    end

    test "session_id is required", %{project: project} do
      assert {:error, _} =
               Ash.create(SessionSlice, %{
                 project_id: project.id,
                 title: "No session"
               })
    end

    test "has default context sizes", %{session: session, project: project} do
      {:ok, slice} =
        Ash.create(SessionSlice, %{
          session_id: session.id,
          project_id: project.id,
          title: "Defaults"
        })

      assert is_integer(slice.context_before_lines)
      assert is_integer(slice.context_after_lines)
    end
  end
end
