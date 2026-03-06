defmodule Spotter.Transcripts.RetroItemTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.RetroItem

  setup do
    :ok = Sandbox.checkout(Spotter.Repo)

    project =
      Ash.create!(Spotter.Transcripts.Project, %{name: "retro-item-test", pattern: "^retro"})

    session =
      Ash.create!(Spotter.Transcripts.Session, %{
        session_id: Ash.UUID.generate(),
        project_id: project.id
      })

    submission =
      Ash.create!(Spotter.Transcripts.RetroSubmission, %{
        submitted_at: ~U[2026-02-26 12:00:00Z],
        session_id: session.id,
        project_id: project.id
      })

    %{project: project, session: session, submission: submission}
  end

  describe "create" do
    test "creates an item with all required fields", %{submission: submission} do
      item =
        Ash.create!(RetroItem, %{
          category: :knowledge_gained,
          observation: "Learned about Ash resources",
          explanation: "Ash makes CRUD simple with declarative DSL",
          retro_submission_id: submission.id
        })

      assert item.id != nil
      assert item.category == :knowledge_gained
      assert item.observation == "Learned about Ash resources"
      assert item.explanation == "Ash makes CRUD simple with declarative DSL"
      assert item.rating == :undecided
      assert item.retro_submission_id == submission.id
    end

    test "rating defaults to :undecided", %{submission: submission} do
      item =
        Ash.create!(RetroItem, %{
          category: :effective_strategy,
          observation: "TDD worked well",
          explanation: "Writing tests first caught bugs early",
          retro_submission_id: submission.id
        })

      assert item.rating == :undecided
    end

    test "accepts explicit rating", %{submission: submission} do
      item =
        Ash.create!(RetroItem, %{
          category: :gotcha,
          observation: "SQLite quirk",
          explanation: "Foreign keys need PRAGMA",
          rating: :useful,
          retro_submission_id: submission.id
        })

      assert item.rating == :useful
    end

    test "accepts all valid categories", %{submission: submission} do
      categories = [
        :knowledge_gained,
        :effective_strategy,
        :gotcha,
        :requirements_clarity,
        :struggle
      ]

      for category <- categories do
        item =
          Ash.create!(RetroItem, %{
            category: category,
            observation: "obs for #{category}",
            explanation: "exp for #{category}",
            retro_submission_id: submission.id
          })

        assert item.category == category
      end
    end

    test "rejects invalid category", %{submission: submission} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(RetroItem, %{
          category: :invalid_category,
          observation: "obs",
          explanation: "exp",
          retro_submission_id: submission.id
        })
      end
    end

    test "category is required", %{submission: submission} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(RetroItem, %{
          observation: "obs",
          explanation: "exp",
          retro_submission_id: submission.id
        })
      end
    end

    test "observation is required", %{submission: submission} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(RetroItem, %{
          category: :gotcha,
          explanation: "exp",
          retro_submission_id: submission.id
        })
      end
    end

    test "explanation is required", %{submission: submission} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(RetroItem, %{
          category: :gotcha,
          observation: "obs",
          retro_submission_id: submission.id
        })
      end
    end

    test "retro_submission_id is required" do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.create!(RetroItem, %{
          category: :gotcha,
          observation: "obs",
          explanation: "exp"
        })
      end
    end
  end

  describe "session traversal through retro_submission" do
    test "loading :session on a retro item returns the originating session", %{
      session: session,
      submission: submission
    } do
      item =
        Ash.create!(RetroItem, %{
          category: :knowledge_gained,
          observation: "Session link test",
          explanation: "Verifies RetroItem -> Session traversal",
          retro_submission_id: submission.id
        })

      loaded = Ash.load!(item, :session)
      assert loaded.session.id == session.id
      assert loaded.session.project_id == session.project_id
    end

    test "items from different submissions resolve to their respective sessions", %{
      project: project
    } do
      session_a =
        Ash.create!(Spotter.Transcripts.Session, %{
          session_id: Ash.UUID.generate(),
          project_id: project.id
        })

      session_b =
        Ash.create!(Spotter.Transcripts.Session, %{
          session_id: Ash.UUID.generate(),
          project_id: project.id
        })

      sub_a =
        Ash.create!(Spotter.Transcripts.RetroSubmission, %{
          submitted_at: ~U[2026-03-01 10:00:00Z],
          session_id: session_a.id,
          project_id: project.id
        })

      sub_b =
        Ash.create!(Spotter.Transcripts.RetroSubmission, %{
          submitted_at: ~U[2026-03-01 11:00:00Z],
          session_id: session_b.id,
          project_id: project.id
        })

      item_a =
        Ash.create!(RetroItem, %{
          category: :knowledge_gained,
          observation: "From session A",
          explanation: "First session",
          retro_submission_id: sub_a.id
        })

      item_b =
        Ash.create!(RetroItem, %{
          category: :gotcha,
          observation: "From session B",
          explanation: "Second session",
          retro_submission_id: sub_b.id
        })

      [loaded_a, loaded_b] = Ash.load!([item_a, item_b], :session)
      assert loaded_a.session.id == session_a.id
      assert loaded_b.session.id == session_b.id
    end

    test "loaded session belongs to the same project as the submission", %{
      project: project,
      session: session,
      submission: submission
    } do
      item =
        Ash.create!(RetroItem, %{
          category: :effective_strategy,
          observation: "Scope check",
          explanation: "Verifies project consistency",
          retro_submission_id: submission.id
        })

      loaded = Ash.load!(item, [:session, :retro_submission])
      assert loaded.session.project_id == project.id
      assert loaded.retro_submission.project_id == project.id
      assert loaded.session.id == session.id
    end
  end

  describe "relationships" do
    test "belongs_to retro_submission is loadable", %{submission: submission} do
      item =
        Ash.create!(RetroItem, %{
          category: :struggle,
          observation: "Hard to debug",
          explanation: "Error messages were cryptic",
          retro_submission_id: submission.id
        })

      loaded = Ash.load!(item, :retro_submission)
      assert loaded.retro_submission.id == submission.id
    end

    test "items are loadable through submission has_many", %{submission: submission} do
      Ash.create!(RetroItem, %{
        category: :knowledge_gained,
        observation: "obs1",
        explanation: "exp1",
        retro_submission_id: submission.id
      })

      Ash.create!(RetroItem, %{
        category: :gotcha,
        observation: "obs2",
        explanation: "exp2",
        retro_submission_id: submission.id
      })

      loaded = Ash.load!(submission, :items)
      assert length(loaded.items) == 2
    end
  end
end
