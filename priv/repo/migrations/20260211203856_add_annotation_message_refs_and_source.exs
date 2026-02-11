defmodule Spotter.Repo.Migrations.AddAnnotationMessageRefsAndSource do
  @moduledoc """
  Adds source column and nullable coordinates to annotations, plus annotation_message_refs table.

  SQLite cannot alter column nullability, so we recreate the annotations table.
  """

  use Ecto.Migration

  def up do
    # Recreate annotations with source column and nullable coordinates
    execute("ALTER TABLE annotations RENAME TO annotations_old")

    execute("""
    CREATE TABLE annotations (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL REFERENCES sessions(id),
      source TEXT NOT NULL DEFAULT 'terminal',
      selected_text TEXT NOT NULL,
      start_row INTEGER,
      start_col INTEGER,
      end_row INTEGER,
      end_col INTEGER,
      comment TEXT NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO annotations (id, session_id, source, selected_text, start_row, start_col, end_row, end_col, comment, inserted_at, updated_at)
    SELECT id, session_id, 'terminal', selected_text, start_row, start_col, end_row, end_col, comment, inserted_at, updated_at
    FROM annotations_old
    """)

    execute("DROP TABLE annotations_old")
    execute("CREATE INDEX annotations_session_id_index ON annotations(session_id)")

    # Create annotation_message_refs
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
    CREATE UNIQUE INDEX annotation_message_refs_unique_annotation_message_index
    ON annotation_message_refs(annotation_id, message_id)
    """)

    execute(
      "CREATE INDEX annotation_message_refs_annotation_id_index ON annotation_message_refs(annotation_id)"
    )

    execute(
      "CREATE INDEX annotation_message_refs_message_id_index ON annotation_message_refs(message_id)"
    )
  end

  def down do
    execute("DROP TABLE IF EXISTS annotation_message_refs")

    execute("ALTER TABLE annotations RENAME TO annotations_old")

    execute("""
    CREATE TABLE annotations (
      id TEXT PRIMARY KEY,
      session_id TEXT NOT NULL REFERENCES sessions(id),
      selected_text TEXT NOT NULL,
      start_row INTEGER NOT NULL,
      start_col INTEGER NOT NULL,
      end_row INTEGER NOT NULL,
      end_col INTEGER NOT NULL,
      comment TEXT NOT NULL,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """)

    execute("""
    INSERT INTO annotations (id, session_id, selected_text, start_row, start_col, end_row, end_col, comment, inserted_at, updated_at)
    SELECT id, session_id, selected_text, start_row, start_col, end_row, end_col, comment, inserted_at, updated_at
    FROM annotations_old
    WHERE start_row IS NOT NULL
    """)

    execute("DROP TABLE annotations_old")
    execute("CREATE INDEX annotations_session_id_index ON annotations(session_id)")
  end
end
