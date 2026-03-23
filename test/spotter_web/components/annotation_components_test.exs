defmodule SpotterWeb.AnnotationComponentsTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias SpotterWeb.AnnotationComponents

  @endpoint SpotterWeb.Endpoint

  describe "annotation_cards explain streaming guard" do
    test "persisted answer takes priority over empty stream entry" do
      annotation = %{
        id: "ann-1",
        source: :transcript,
        purpose: :explain,
        selected_text: "some code",
        comment: "explain this",
        metadata: %{"explain" => %{"status" => "complete", "answer" => "The answer is 42."}},
        message_refs: [],
        inserted_at: ~U[2026-02-16 10:00:00Z]
      }

      html =
        render_component(&AnnotationComponents.annotation_cards/1,
          annotations: [annotation],
          explain_streams: %{"ann-1" => ""}
        )

      assert html =~ "The answer is 42."
      refute html =~ "Explaining..."
    end

    test "non-empty stream shown when no persisted answer" do
      annotation = %{
        id: "ann-2",
        source: :transcript,
        purpose: :explain,
        selected_text: "some code",
        comment: "explain this",
        metadata: %{"explain" => %{"status" => "pending"}},
        message_refs: [],
        inserted_at: ~U[2026-02-16 10:00:00Z]
      }

      html =
        render_component(&AnnotationComponents.annotation_cards/1,
          annotations: [annotation],
          explain_streams: %{"ann-2" => "Partial stream content"}
        )

      assert html =~ "Explaining..."
      assert html =~ "Partial stream content"
    end

    test "empty stream with no answer shows Explaining indicator" do
      annotation = %{
        id: "ann-3",
        source: :transcript,
        purpose: :explain,
        selected_text: "some code",
        comment: "explain this",
        metadata: %{"explain" => %{"status" => "pending"}},
        message_refs: [],
        inserted_at: ~U[2026-02-16 10:00:00Z]
      }

      html =
        render_component(&AnnotationComponents.annotation_cards/1,
          annotations: [annotation],
          explain_streams: %{"ann-3" => ""}
        )

      assert html =~ "Explaining..."
    end
  end

  describe "source_badge_text/1" do
    test "returns 'Feedback' for :product_feedback source" do
      assert AnnotationComponents.source_badge_text(:product_feedback) == "Feedback"
    end

    test "returns 'Transcript' for :transcript source" do
      assert AnnotationComponents.source_badge_text(:transcript) == "Transcript"
    end

    test "returns 'File' for :file source" do
      assert AnnotationComponents.source_badge_text(:file) == "File"
    end

    test "capitalizes unknown atom sources" do
      assert AnnotationComponents.source_badge_text(:plan) == "Plan"
    end
  end
end
