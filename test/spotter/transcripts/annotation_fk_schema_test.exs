defmodule Spotter.Transcripts.AnnotationFkSchemaTest do
  use Spotter.DataCase, async: false

  alias Ecto.Adapters.SQL

  test "annotation-linked tables reference annotations(id), not annotations_old" do
    assert_annotation_fk_target("annotation_file_refs")
    assert_annotation_fk_target("annotation_message_refs")
    assert_annotation_fk_target("flashcards")
  end

  defp assert_annotation_fk_target(table) do
    rows = foreign_key_rows(table)

    refute Enum.any?(rows, fn row -> Enum.at(row, 2) == "annotations_old" end)

    assert Enum.any?(rows, fn row ->
             Enum.at(row, 2) == "annotations" and
               Enum.at(row, 3) == "annotation_id" and
               Enum.at(row, 4) == "id"
           end),
           "expected #{table}.annotation_id to reference annotations(id), got: #{inspect(rows)}"
  end

  defp foreign_key_rows(table) do
    SQL.query!(Repo, "PRAGMA foreign_key_list('#{table}')", []).rows
  end
end
