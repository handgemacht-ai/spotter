defmodule Spotter.Transcripts.RetroSubmissionTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.RetroSubmission

  setup do
    :ok = Sandbox.checkout(Spotter.Repo)

    project = Ash.create!(Spotter.Transcripts.Project, %{name: "retro-test", pattern: "^retro"})

    session =
      Ash.create!(Spotter.Transcripts.Session, %{
        session_id: Ash.UUID.generate(),
        project_id: project.id
      })

    %{project: project, session: session}
  end

  describe "read" do
    test "Ash.read! returns empty list when no submissions exist" do
      assert Ash.read!(RetroSubmission) == []
    end
  end

  describe "create" do
    test "creates a submission with required fields", %{project: project, session: session} do
      submission =
        Ash.create!(RetroSubmission, %{
          submitted_at: ~U[2026-02-26 12:00:00Z],
          session_id: session.id,
          project_id: project.id
        })

      assert submission.id != nil
      assert submission.submitted_at == ~U[2026-02-26 12:00:00.000000Z]
      assert submission.session_id == session.id
      assert submission.project_id == project.id
      assert submission.summary == nil
    end

    test "creates a submission with optional summary", %{project: project, session: session} do
      submission =
        Ash.create!(RetroSubmission, %{
          summary: "Good session overall",
          submitted_at: ~U[2026-02-26 12:00:00Z],
          session_id: session.id,
          project_id: project.id
        })

      assert submission.summary == "Good session overall"
    end

    test "submitted_at is required", %{project: project, session: session} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(RetroSubmission, %{
          session_id: session.id,
          project_id: project.id
        })
      end
    end

    test "session_id is required", %{project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(RetroSubmission, %{
          submitted_at: ~U[2026-02-26 12:00:00Z],
          project_id: project.id
        })
      end
    end

    test "project_id is required", %{session: session} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(RetroSubmission, %{
          submitted_at: ~U[2026-02-26 12:00:00Z],
          session_id: session.id
        })
      end
    end
  end

  describe "relationships" do
    test "has_many items is loadable", %{project: project, session: session} do
      submission =
        Ash.create!(RetroSubmission, %{
          submitted_at: ~U[2026-02-26 12:00:00Z],
          session_id: session.id,
          project_id: project.id
        })

      loaded = Ash.load!(submission, :items)
      assert loaded.items == []
    end

    test "belongs_to session is loadable", %{project: project, session: session} do
      submission =
        Ash.create!(RetroSubmission, %{
          submitted_at: ~U[2026-02-26 12:00:00Z],
          session_id: session.id,
          project_id: project.id
        })

      loaded = Ash.load!(submission, :session)
      assert loaded.session.id == session.id
    end

    test "belongs_to project is loadable", %{project: project, session: session} do
      submission =
        Ash.create!(RetroSubmission, %{
          submitted_at: ~U[2026-02-26 12:00:00Z],
          session_id: session.id,
          project_id: project.id
        })

      loaded = Ash.load!(submission, :project)
      assert loaded.project.id == project.id
    end
  end
end
