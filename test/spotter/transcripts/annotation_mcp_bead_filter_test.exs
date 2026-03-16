defmodule Spotter.Transcripts.AnnotationMcpBeadFilterTest do
  use Spotter.DataCase, async: false

  require Ash.Query

  alias Spotter.Transcripts.{Annotation, Project}

  setup do
    project = Ash.create!(Project, %{name: "test-mcp-bead-filter", pattern: "^test"})

    plan_annotation =
      Ash.create!(Annotation, %{
        source: :plan,
        bead_id: "mcp-bead-1",
        selected_text: "plan text",
        comment: "plan review",
        project_id: project.id,
        state: :open,
        purpose: :review
      })

    other_plan_annotation =
      Ash.create!(Annotation, %{
        source: :plan,
        bead_id: "mcp-bead-2",
        selected_text: "other plan text",
        comment: "different bead review",
        project_id: project.id,
        state: :open,
        purpose: :review
      })

    transcript_annotation =
      Ash.create!(Annotation, %{
        source: :file,
        selected_text: "file content",
        comment: "file review",
        project_id: project.id,
        state: :open,
        purpose: :review
      })

    mcp_context = %{spotter_mcp_scope: %{project_id: project.id}}

    %{
      project: project,
      plan_annotation: plan_annotation,
      other_plan_annotation: other_plan_annotation,
      transcript_annotation: transcript_annotation,
      mcp_context: mcp_context
    }
  end

  describe "mcp_read_review_annotations with bead_id filter" do
    test "nil bead_id returns all review annotations (backward compat)", %{
      mcp_context: mcp_context,
      plan_annotation: plan_annotation,
      other_plan_annotation: other_plan_annotation,
      transcript_annotation: transcript_annotation
    } do
      assert {:ok, results} =
               Annotation
               |> Ash.Query.new()
               |> Ash.Query.set_context(mcp_context)
               |> Ash.Query.for_read(:mcp_read_review_annotations)
               |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert plan_annotation.id in ids
      assert other_plan_annotation.id in ids
      assert transcript_annotation.id in ids
    end

    test "specific bead_id filters to only matching annotations", %{
      mcp_context: mcp_context,
      plan_annotation: plan_annotation,
      other_plan_annotation: other_plan_annotation,
      transcript_annotation: transcript_annotation
    } do
      assert {:ok, results} =
               Annotation
               |> Ash.Query.new()
               |> Ash.Query.set_context(mcp_context)
               |> Ash.Query.for_read(:mcp_read_review_annotations, %{bead_id: "mcp-bead-1"})
               |> Ash.read()

      ids = Enum.map(results, & &1.id)
      assert plan_annotation.id in ids
      refute other_plan_annotation.id in ids
      refute transcript_annotation.id in ids
    end

    test "nonexistent bead_id returns empty list", %{mcp_context: mcp_context} do
      assert {:ok, []} =
               Annotation
               |> Ash.Query.new()
               |> Ash.Query.set_context(mcp_context)
               |> Ash.Query.for_read(:mcp_read_review_annotations, %{bead_id: "nonexistent-bead"})
               |> Ash.read()
    end
  end
end
