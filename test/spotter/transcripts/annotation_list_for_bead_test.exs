defmodule Spotter.Transcripts.AnnotationListForBeadTest do
  use Spotter.DataCase, async: false

  require Ash.Query

  alias Spotter.Transcripts.{Annotation, Project}

  setup do
    project = Ash.create!(Project, %{name: "test-list-for-bead", pattern: "^test"})

    bead_annotation =
      Ash.create!(Annotation, %{
        source: :plan,
        bead_id: "test-bead-1",
        selected_text: "plan item text",
        comment: "review this plan item",
        project_id: project.id,
        state: :open
      })

    other_bead_annotation =
      Ash.create!(Annotation, %{
        source: :plan,
        bead_id: "test-bead-2",
        selected_text: "other plan text",
        comment: "different bead",
        project_id: project.id,
        state: :open
      })

    closed_annotation =
      Ash.create!(Annotation, %{
        source: :plan,
        bead_id: "test-bead-1",
        selected_text: "closed plan text",
        comment: "already resolved",
        project_id: project.id,
        state: :closed
      })

    file_annotation =
      Ash.create!(Annotation, %{
        source: :file,
        selected_text: "file content",
        comment: "file annotation",
        project_id: project.id
      })

    %{
      project: project,
      bead_annotation: bead_annotation,
      other_bead_annotation: other_bead_annotation,
      closed_annotation: closed_annotation,
      file_annotation: file_annotation
    }
  end

  describe ":list_for_bead action" do
    test "returns only open plan annotations for the given bead_id", %{
      bead_annotation: bead_annotation
    } do
      assert {:ok, results} =
               Annotation
               |> Ash.Query.for_read(:list_for_bead, %{bead_id: "test-bead-1"})
               |> Ash.read()

      assert length(results) == 1
      assert hd(results).id == bead_annotation.id
      assert hd(results).bead_id == "test-bead-1"
      assert hd(results).source == :plan
      assert hd(results).state == :open
    end

    test "does not return annotations for different bead_id", %{
      other_bead_annotation: other_bead_annotation
    } do
      assert {:ok, results} =
               Annotation
               |> Ash.Query.for_read(:list_for_bead, %{bead_id: "test-bead-2"})
               |> Ash.read()

      assert length(results) == 1
      assert hd(results).id == other_bead_annotation.id
    end

    test "does not return closed annotations" do
      assert {:ok, results} =
               Annotation
               |> Ash.Query.for_read(:list_for_bead, %{bead_id: "test-bead-1"})
               |> Ash.read()

      refute Enum.any?(results, fn r -> r.state == :closed end)
      assert length(results) == 1
    end

    test "does not return non-plan source annotations", %{file_annotation: file_annotation} do
      assert {:ok, results} =
               Annotation
               |> Ash.Query.for_read(:list_for_bead, %{bead_id: "test-bead-1"})
               |> Ash.read()

      ids = Enum.map(results, & &1.id)
      refute file_annotation.id in ids
    end

    test "returns empty list for unknown bead_id" do
      assert {:ok, []} =
               Annotation
               |> Ash.Query.for_read(:list_for_bead, %{bead_id: "nonexistent-bead"})
               |> Ash.read()
    end
  end
end
