defmodule Spotter.Transcripts.AnnotationResolveTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Annotation, Project, Session}

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "test-resolve", pattern: "^test"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

    annotation =
      Ash.create!(Annotation, %{
        session_id: session.id,
        source: :transcript,
        selected_text: "some code",
        comment: "needs review",
        metadata: %{"existing_key" => "existing_value"}
      })

    %{annotation: annotation}
  end

  describe "resolve action" do
    test "closes the annotation", %{annotation: annotation} do
      resolved = Ash.update!(annotation, %{resolution: "Fixed the issue"}, action: :resolve)

      assert resolved.state == :closed
    end

    test "preserves existing metadata keys", %{annotation: annotation} do
      resolved = Ash.update!(annotation, %{resolution: "Fixed it"}, action: :resolve)

      assert resolved.metadata["existing_key"] == "existing_value"
    end

    test "writes required metadata keys", %{annotation: annotation} do
      resolved =
        Ash.update!(
          annotation,
          %{resolution: "Changed the code", resolution_kind: :code_change},
          action: :resolve
        )

      assert resolved.metadata["resolution"] == "Changed the code"
      assert resolved.metadata["resolution_kind"] == "code_change"
      assert resolved.metadata["resolved_at"] != nil

      {:ok, _dt, _offset} = DateTime.from_iso8601(resolved.metadata["resolved_at"])
    end

    test "resolution_kind is optional", %{annotation: annotation} do
      resolved = Ash.update!(annotation, %{resolution: "Fixed it"}, action: :resolve)

      assert resolved.metadata["resolution"] == "Fixed it"
      refute Map.has_key?(resolved.metadata, "resolution_kind")
    end

    test "calling resolve twice overwrites resolution and updates resolved_at", %{
      annotation: annotation
    } do
      first = Ash.update!(annotation, %{resolution: "First fix"}, action: :resolve)
      first_resolved_at = first.metadata["resolved_at"]

      Process.sleep(10)

      second = Ash.update!(first, %{resolution: "Better fix"}, action: :resolve)

      assert second.metadata["resolution"] == "Better fix"
      assert second.metadata["resolved_at"] != first_resolved_at
      assert second.state == :closed
    end

    test "rejects blank/whitespace-only resolution", %{annotation: annotation} do
      assert {:error, _error} =
               Ash.update(annotation, %{resolution: "   "}, action: :resolve)
    end

    test "trims whitespace from resolution", %{annotation: annotation} do
      resolved = Ash.update!(annotation, %{resolution: "  Fixed it  "}, action: :resolve)

      assert resolved.metadata["resolution"] == "Fixed it"
    end
  end
end
