defmodule Spotter.Repo.Migrations.RepairAnnotationFkTargets do
  @moduledoc """
  Repairs annotation-linked SQLite foreign keys that may drift to annotations_old
  after table-rewrite migrations.
  """

  use Ecto.Migration

  def up do
    rebuild_annotation_file_refs()
    rebuild_annotation_message_refs()
    rebuild_flashcards()
  end

  def down do
    raise """
    Irreversible migration: this repair rewrites annotation-linked tables to enforce
    foreign keys to annotations(id). Reverting may reintroduce invalid references.
    """
  end

  defp rebuild_annotation_file_refs do
    execute("ALTER TABLE annotation_file_refs RENAME TO annotation_file_refs_old")

    execute("""
    CREATE TABLE annotation_file_refs (
      project_id TEXT NOT NULL CONSTRAINT annotation_file_refs_project_id_fkey REFERENCES projects(id),
      annotation_id TEXT NOT NULL CONSTRAINT annotation_file_refs_annotation_id_fkey REFERENCES annotations(id),
      updated_at TEXT NOT NULL,
      inserted_at TEXT NOT NULL,
      line_end INTEGER NOT NULL,
      line_start INTEGER NOT NULL,
      relative_path TEXT NOT NULL,
      id TEXT NOT NULL PRIMARY KEY
    )
    """)

    execute("""
    INSERT INTO annotation_file_refs (
      project_id,
      annotation_id,
      updated_at,
      inserted_at,
      line_end,
      line_start,
      relative_path,
      id
    )
    SELECT
      old.project_id,
      old.annotation_id,
      old.updated_at,
      old.inserted_at,
      old.line_end,
      old.line_start,
      old.relative_path,
      old.id
    FROM annotation_file_refs_old AS old
    INNER JOIN annotations AS a ON a.id = old.annotation_id
    INNER JOIN projects AS p ON p.id = old.project_id
    """)

    execute("DROP TABLE annotation_file_refs_old")

    execute("""
    CREATE UNIQUE INDEX annotation_file_refs_unique_annotation_file_ref_index
    ON annotation_file_refs(annotation_id, relative_path, line_start, line_end)
    """)
  end

  defp rebuild_annotation_message_refs do
    execute("ALTER TABLE annotation_message_refs RENAME TO annotation_message_refs_old")

    execute("""
    CREATE TABLE annotation_message_refs (
      id TEXT PRIMARY KEY,
      annotation_id TEXT NOT NULL REFERENCES annotations(id),
      message_id TEXT NOT NULL REFERENCES messages(id),
      ordinal INTEGER NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO annotation_message_refs (
      id,
      annotation_id,
      message_id,
      ordinal,
      inserted_at,
      updated_at
    )
    SELECT
      old.id,
      old.annotation_id,
      old.message_id,
      old.ordinal,
      old.inserted_at,
      old.updated_at
    FROM annotation_message_refs_old AS old
    INNER JOIN annotations AS a ON a.id = old.annotation_id
    INNER JOIN messages AS m ON m.id = old.message_id
    """)

    execute("DROP TABLE annotation_message_refs_old")

    execute("""
    CREATE UNIQUE INDEX annotation_message_refs_unique_annotation_message_index
    ON annotation_message_refs(annotation_id, message_id)
    """)

    execute("""
    CREATE INDEX annotation_message_refs_annotation_id_index
    ON annotation_message_refs(annotation_id)
    """)

    execute("""
    CREATE INDEX annotation_message_refs_message_id_index
    ON annotation_message_refs(message_id)
    """)
  end

  defp rebuild_flashcards do
    execute("ALTER TABLE flashcards RENAME TO flashcards_old")

    execute("""
    CREATE TABLE flashcards (
      annotation_id TEXT NOT NULL CONSTRAINT flashcards_annotation_id_fkey REFERENCES annotations(id),
      project_id TEXT NOT NULL CONSTRAINT flashcards_project_id_fkey REFERENCES projects(id),
      updated_at TEXT NOT NULL,
      inserted_at TEXT NOT NULL,
      "references" TEXT DEFAULT ('{}') NOT NULL,
      answer TEXT NOT NULL,
      front_snippet TEXT NOT NULL,
      question TEXT,
      id TEXT NOT NULL PRIMARY KEY
    )
    """)

    execute("""
    INSERT INTO flashcards (
      annotation_id,
      project_id,
      updated_at,
      inserted_at,
      "references",
      answer,
      front_snippet,
      question,
      id
    )
    SELECT
      old.annotation_id,
      old.project_id,
      old.updated_at,
      old.inserted_at,
      old."references",
      old.answer,
      old.front_snippet,
      old.question,
      old.id
    FROM flashcards_old AS old
    INNER JOIN annotations AS a ON a.id = old.annotation_id
    INNER JOIN projects AS p ON p.id = old.project_id
    """)

    execute("DROP TABLE flashcards_old")

    execute("""
    CREATE UNIQUE INDEX flashcards_unique_flashcard_per_annotation_index
    ON flashcards(annotation_id)
    """)
  end
end
