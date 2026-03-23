defmodule Spotter.ImageStoreTest do
  use Spotter.DataCase, async: false

  alias Spotter.ImageStore
  alias Spotter.Transcripts.{Annotation, Project, Session}

  setup do
    project = Ash.create!(Project, %{name: "test-image-store", pattern: "^test"})

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
        comment: "needs image"
      })

    %{annotation: annotation, session: session, project: project}
  end

  describe "store/2 and fetch/1" do
    test "stores valid PNG binary and fetches it back", %{annotation: annotation} do
      png_binary = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 1>>

      assert {:ok, ref} = ImageStore.store(png_binary, annotation.id)
      assert is_binary(ref)

      assert {:ok, fetched} = ImageStore.fetch(ref)
      assert fetched == png_binary
    end
  end

  describe "fetch/1 with invalid ref" do
    test "returns :not_found for nonexistent reference" do
      assert {:error, :not_found} = ImageStore.fetch("nonexistent-ref")
    end
  end

  describe "delete/1" do
    test "deletes stored image and subsequent fetch returns :not_found", %{
      annotation: annotation
    } do
      png_binary = <<137, 80, 78, 71, 13, 10, 26, 10>>

      {:ok, ref} = ImageStore.store(png_binary, annotation.id)
      assert :ok = ImageStore.delete(ref)
      assert {:error, :not_found} = ImageStore.fetch(ref)
    end
  end

  describe "upsert behavior" do
    test "second store for same annotation_id replaces first", %{annotation: annotation} do
      first_binary = <<1, 2, 3, 4>>
      second_binary = <<5, 6, 7, 8>>

      {:ok, ref1} = ImageStore.store(first_binary, annotation.id)
      {:ok, ref2} = ImageStore.store(second_binary, annotation.id)

      assert ref1 == ref2

      {:ok, fetched} = ImageStore.fetch(ref2)
      assert fetched == second_binary
    end
  end

  describe "size limit" do
    test "rejects binary larger than 5MB" do
      oversized = :binary.copy(<<0>>, 5 * 1024 * 1024 + 1)
      annotation_id = Ash.UUID.generate()

      assert {:error, :too_large} = ImageStore.store(oversized, annotation_id)
    end
  end

  describe "annotation image_ref attribute" do
    test "annotation accepts image_ref on create", %{session: session} do
      annotation =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :transcript,
          selected_text: "code with image",
          comment: "has image ref",
          image_ref: "some-image-ref"
        })

      assert annotation.image_ref == "some-image-ref"
    end
  end
end
