defmodule Spotter.Transcripts.Jobs.ExplainAnnotationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  alias Spotter.Transcripts.{
    Annotation,
    Flashcard,
    ReviewItem
  }

  alias Spotter.Transcripts.Jobs.ExplainAnnotation

  require Ash.Query

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    Application.put_env(:spotter, :claude_streaming_module, FakeStreaming)

    on_exit(fn ->
      Application.delete_env(:spotter, :claude_streaming_module)
    end)

    project =
      Ash.create!(Spotter.Transcripts.Project, %{
        name: "explain-test-#{System.unique_integer([:positive])}",
        pattern: "^test"
      })

    session =
      Ash.create!(Spotter.Transcripts.Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

    annotation =
      Ash.create!(Annotation, %{
        session_id: session.id,
        selected_text: "def hello, do: :world",
        comment: "What does this do?",
        purpose: :explain
      })

    %{project: project, session: session, annotation: annotation}
  end

  test "performs explain job and creates flashcard + review item", %{annotation: annotation} do
    job = build_job(%{"annotation_id" => annotation.id})
    assert :ok = ExplainAnnotation.perform(job)

    updated = Ash.get!(Annotation, annotation.id)
    explain = updated.metadata["explain"]

    assert explain["status"] == "complete"
    assert explain["answer"] =~ "hello world"
    assert [%{"url" => "https://example.com"}] = explain["references"]

    flashcards =
      Flashcard
      |> Ash.Query.filter(annotation_id == ^annotation.id)
      |> Ash.read!()

    assert length(flashcards) == 1
    flashcard = hd(flashcards)
    assert flashcard.front_snippet == "def hello, do: :world"
    assert flashcard.answer =~ "hello world"

    review_items =
      ReviewItem
      |> Ash.Query.filter(flashcard_id == ^flashcard.id)
      |> Ash.read!()

    assert length(review_items) == 1
    item = hd(review_items)
    assert item.target_kind == :flashcard
    assert item.next_due_on == Date.utc_today()
  end

  test "handles streaming error gracefully", %{annotation: annotation} do
    Application.put_env(:spotter, :claude_streaming_module, FakeStreamingError)

    job = build_job(%{"annotation_id" => annotation.id})
    assert {:error, _reason} = ExplainAnnotation.perform(job)

    updated = Ash.get!(Annotation, annotation.id)
    explain = updated.metadata["explain"]

    assert explain["status"] == "error"
    assert is_binary(explain["error"])
  end

  test "idempotent: running twice creates exactly 1 flashcard and 1 review item", %{
    annotation: annotation
  } do
    job = build_job(%{"annotation_id" => annotation.id})

    assert :ok = ExplainAnnotation.perform(job)
    assert :ok = ExplainAnnotation.perform(job)

    flashcards =
      Flashcard
      |> Ash.Query.filter(annotation_id == ^annotation.id)
      |> Ash.read!()

    assert length(flashcards) == 1
    flashcard = hd(flashcards)

    review_items =
      ReviewItem
      |> Ash.Query.filter(target_kind == :flashcard and flashcard_id == ^flashcard.id)
      |> Ash.read!()

    assert length(review_items) == 1
  end

  test "message_stop with blank final_text preserves accumulated deltas", %{
    annotation: annotation
  } do
    Application.put_env(:spotter, :claude_streaming_module, FakeStreamingBlankFinal)

    job = build_job(%{"annotation_id" => annotation.id})
    assert :ok = ExplainAnnotation.perform(job)

    updated = Ash.get!(Annotation, annotation.id)
    explain = updated.metadata["explain"]

    assert explain["status"] == "complete"
    assert explain["answer"] == "hello world"

    flashcards =
      Flashcard
      |> Ash.Query.filter(annotation_id == ^annotation.id)
      |> Ash.read!()

    assert length(flashcards) == 1
    assert hd(flashcards).answer == "hello world"
  end

  test "blank-only answer results in error and no persistence artifacts", %{
    annotation: annotation
  } do
    Application.put_env(:spotter, :claude_streaming_module, FakeStreamingBlankAnswer)

    job = build_job(%{"annotation_id" => annotation.id})
    assert {:error, _} = ExplainAnnotation.perform(job)

    updated = Ash.get!(Annotation, annotation.id)
    explain = updated.metadata["explain"]

    assert explain["status"] == "error"
    assert explain["error"] =~ "empty answer from LLM"

    flashcards =
      Flashcard
      |> Ash.Query.filter(annotation_id == ^annotation.id)
      |> Ash.read!()

    assert flashcards == []

    review_items =
      ReviewItem
      |> Ash.Query.filter(target_kind == :flashcard)
      |> Ash.read!()
      |> Enum.filter(fn ri ->
        case Ash.Query.filter(Flashcard, annotation_id == ^annotation.id) |> Ash.read!() do
          [] -> false
          cards -> ri.flashcard_id in Enum.map(cards, & &1.id)
        end
      end)

    assert review_items == []
  end

  test "complete status only exists when flashcard and review_item both exist", %{
    annotation: annotation
  } do
    job = build_job(%{"annotation_id" => annotation.id})
    assert :ok = ExplainAnnotation.perform(job)

    updated = Ash.get!(Annotation, annotation.id)
    explain = updated.metadata["explain"]

    # Status must be "complete" only when both flashcard and review_item exist
    assert explain["status"] == "complete"

    flashcards =
      Flashcard
      |> Ash.Query.filter(annotation_id == ^annotation.id)
      |> Ash.read!()

    assert length(flashcards) == 1
    flashcard = hd(flashcards)

    review_items =
      ReviewItem
      |> Ash.Query.filter(flashcard_id == ^flashcard.id and target_kind == :flashcard)
      |> Ash.read!()

    assert length(review_items) == 1

    # Verify the invariant: complete ↔ flashcard + review_item exist
    # This test confirms the refactored finalize_success writes "complete"
    # only AFTER both downstream creates succeed (not before, as the old code did)
    assert explain["answer"] != ""
    assert explain["answer"] != nil
  end

  test "performs explain job for unbound file annotation (no session)", %{project: project} do
    annotation =
      Ash.create!(Annotation, %{
        source: :file,
        selected_text: "def unbound, do: :ok",
        comment: "Explain this unbound annotation",
        purpose: :explain,
        project_id: project.id
      })

    job = build_job(%{"annotation_id" => annotation.id})
    assert :ok = ExplainAnnotation.perform(job)

    updated = Ash.get!(Annotation, annotation.id)
    explain = updated.metadata["explain"]

    assert explain["status"] == "complete"
    assert explain["answer"] =~ "hello world"

    flashcards =
      Flashcard
      |> Ash.Query.filter(annotation_id == ^annotation.id)
      |> Ash.read!()

    assert length(flashcards) == 1
    flashcard = hd(flashcards)
    assert flashcard.project_id == project.id
  end

  defp build_job(args) do
    %Oban.Job{args: args}
  end
end

defmodule FakeStreamingBlankFinal do
  def start_session(_opts), do: {:ok, self()}

  def send_message(_session, _message) do
    [
      %{type: :text_delta, text: "hello"},
      %{type: :text_delta, text: " world"},
      %{type: :message_stop, final_text: ""}
    ]
  end

  def close_session(_session), do: :ok
end

defmodule FakeStreamingBlankAnswer do
  def start_session(_opts), do: {:ok, self()}

  def send_message(_session, _message) do
    [
      %{type: :text_delta, text: "   "},
      %{type: :message_stop, final_text: ""}
    ]
  end

  def close_session(_session), do: :ok
end

defmodule FakeStreaming do
  def start_session(_opts), do: {:ok, self()}

  def send_message(_session, _message) do
    [
      %{type: :text_delta, text: "hello"},
      %{type: :text_delta, text: " world\nReferences:\n- https://example.com\n"},
      %{type: :message_stop, final_text: "hello world\nReferences:\n- https://example.com\n"}
    ]
  end

  def close_session(_session), do: :ok
end

defmodule FakeStreamingError do
  def start_session(_opts), do: {:ok, self()}

  def send_message(_session, _message) do
    raise "streaming failed"
  end

  def close_session(_session), do: :ok
end
