defmodule Spotter.Transcripts.AnnotationProductFeedbackTest do
  use Spotter.DataCase, async: false

  require Ash.Query

  alias Spotter.Transcripts.{Annotation, Project}

  setup do
    project = Ash.create!(Project, %{name: "test-product-feedback", pattern: "^test"})

    %{project: project}
  end

  describe "product_feedback source without session_id" do
    test "creates annotation with source=:product_feedback without session_id", %{
      project: project
    } do
      annotation =
        Ash.create!(Annotation, %{
          source: :product_feedback,
          selected_text: "user reported issue",
          comment: "feedback from user testing",
          project_id: project.id
        })

      assert annotation.source == :product_feedback
      assert is_nil(annotation.session_id)
      assert annotation.project_id == project.id
    end
  end

  describe "bead_id flexibility for product_feedback" do
    test "product_feedback accepts optional bead_id", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          source: :product_feedback,
          bead_id: "spotter-feedback-1",
          selected_text: "user feedback text",
          comment: "linked to a bead",
          project_id: project.id
        })

      assert annotation.source == :product_feedback
      assert annotation.bead_id == "spotter-feedback-1"
    end

    test "product_feedback works without bead_id", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          source: :product_feedback,
          selected_text: "unlinked feedback",
          comment: "no bead association",
          project_id: project.id
        })

      assert annotation.source == :product_feedback
      assert is_nil(annotation.bead_id)
    end
  end

  describe "list_for_bead includes product_feedback" do
    test "returns product_feedback annotations matching bead_id", %{project: project} do
      Ash.create!(Annotation, %{
        source: :product_feedback,
        bead_id: "test-bead-pf",
        selected_text: "feedback text",
        comment: "product feedback for bead",
        project_id: project.id,
        state: :open
      })

      Ash.create!(Annotation, %{
        source: :plan,
        bead_id: "test-bead-pf",
        selected_text: "plan text",
        comment: "plan annotation for same bead",
        project_id: project.id,
        state: :open
      })

      assert {:ok, results} =
               Annotation
               |> Ash.Query.for_read(:list_for_bead, %{bead_id: "test-bead-pf"})
               |> Ash.read()

      assert length(results) == 2
      sources = Enum.map(results, & &1.source) |> Enum.sort()
      assert sources == [:plan, :product_feedback]
    end

    test "does not return closed product_feedback annotations", %{project: project} do
      Ash.create!(Annotation, %{
        source: :product_feedback,
        bead_id: "test-bead-closed",
        selected_text: "closed feedback",
        comment: "already resolved",
        project_id: project.id,
        state: :closed
      })

      assert {:ok, []} =
               Annotation
               |> Ash.Query.for_read(:list_for_bead, %{bead_id: "test-bead-closed"})
               |> Ash.read()
    end
  end

  describe "existing sources unchanged" do
    test "transcript source still requires session_id" do
      assert {:error, _} =
               Ash.create(Annotation, %{
                 source: :transcript,
                 selected_text: "some text",
                 comment: "a comment"
               })
    end
  end
end
