defmodule Spotter.Transcripts.RetroItemRateTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.RetroItem

  setup do
    :ok = Sandbox.checkout(Spotter.Repo)

    project =
      Ash.create!(Spotter.Transcripts.Project, %{name: "retro-rate-test", pattern: "^retro"})

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

    item =
      Ash.create!(RetroItem, %{
        category: :knowledge_gained,
        observation: "Test observation",
        explanation: "Test explanation",
        retro_submission_id: submission.id
      })

    %{item: item, project: project}
  end

  describe "rate action" do
    test "updates rating to :useful", %{item: item} do
      updated = Ash.update!(item, %{rating: :useful}, action: :rate)
      assert updated.rating == :useful
    end

    test "updates rating to :not_useful", %{item: item} do
      updated = Ash.update!(item, %{rating: :not_useful}, action: :rate)
      assert updated.rating == :not_useful
    end

    test "updates rating back to :undecided", %{item: item} do
      rated = Ash.update!(item, %{rating: :useful}, action: :rate)
      reverted = Ash.update!(rated, %{rating: :undecided}, action: :rate)
      assert reverted.rating == :undecided
    end

    test "rejects invalid rating", %{item: item} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.update!(item, %{rating: :invalid}, action: :rate)
      end
    end
  end

  describe "mcp_rate action" do
    test "updates rating to :useful with matching scope", %{item: item, project: project} do
      updated =
        Ash.update!(item, %{rating: :useful},
          action: :mcp_rate,
          context: %{spotter_mcp_scope: %{project_id: project.id}}
        )

      assert updated.rating == :useful
    end

    test "updates rating to :not_useful with matching scope", %{item: item, project: project} do
      updated =
        Ash.update!(item, %{rating: :not_useful},
          action: :mcp_rate,
          context: %{spotter_mcp_scope: %{project_id: project.id}}
        )

      assert updated.rating == :not_useful
    end

    test "rejects invalid rating", %{item: item, project: project} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.update!(item, %{rating: :invalid},
          action: :mcp_rate,
          context: %{spotter_mcp_scope: %{project_id: project.id}}
        )
      end
    end

    test "rejects rating without MCP scope", %{item: item} do
      assert_raise Ash.Error.Invalid, fn ->
        Ash.update!(item, %{rating: :useful}, action: :mcp_rate)
      end
    end

    test "rejects rating with wrong project scope", %{item: item} do
      other_project =
        Ash.create!(Spotter.Transcripts.Project, %{name: "other-rate", pattern: "^other"})

      assert_raise Ash.Error.Invalid, fn ->
        Ash.update!(item, %{rating: :useful},
          action: :mcp_rate,
          context: %{spotter_mcp_scope: %{project_id: other_project.id}}
        )
      end
    end
  end
end
