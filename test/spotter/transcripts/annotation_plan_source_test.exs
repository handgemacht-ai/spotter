defmodule Spotter.Transcripts.AnnotationPlanSourceTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Annotation, Project}

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "test-plan-annotations", pattern: "^test"})

    %{project: project}
  end

  describe "plan source with bead_id" do
    test "creates annotation with source=:plan and bead_id", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          source: :plan,
          bead_id: "spotter-gbb",
          selected_text: "plan item text",
          comment: "review this plan item",
          project_id: project.id
        })

      assert annotation.source == :plan
      assert annotation.bead_id == "spotter-gbb"
      assert annotation.project_id == project.id
    end
  end

  describe "plan annotations without session_id" do
    test "plan annotations are valid without session_id", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          source: :plan,
          bead_id: "spotter-abc",
          selected_text: "some plan text",
          comment: "annotation on plan",
          project_id: project.id
        })

      assert is_nil(annotation.session_id)
      assert annotation.source == :plan
    end
  end

  describe "existing annotation types unchanged" do
    test "transcript source still requires session_id" do
      assert {:error, _} =
               Ash.create(Annotation, %{
                 source: :transcript,
                 selected_text: "some text",
                 comment: "a comment"
               })
    end

    test "file source still works without session_id", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          source: :file,
          selected_text: "file content",
          comment: "file annotation",
          project_id: project.id
        })

      assert annotation.source == :file
      assert is_nil(annotation.session_id)
    end
  end

  describe "MCP resolve returns bead_id for plan annotations" do
    test "mcp_resolve includes bead_id in resolved plan annotation", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          source: :plan,
          bead_id: "spotter-xyz",
          selected_text: "plan text",
          comment: "plan review",
          project_id: project.id
        })

      resolved =
        Ash.update!(
          annotation,
          %{resolution: "Addressed in implementation"},
          action: :mcp_resolve,
          context: %{spotter_mcp_scope: %{project_id: project.id}}
        )

      assert resolved.state == :closed
      assert resolved.bead_id == "spotter-xyz"
      assert resolved.metadata["resolution"] == "Addressed in implementation"
    end
  end
end
