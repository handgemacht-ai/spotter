defmodule Spotter.Repo.Migrations.MakeAnnotationsSessionNullable do
  @moduledoc """
  Makes session_id nullable on annotations for unbound file annotations.

  SQLite cannot ALTER COLUMN nullability, so we use the table-rewrite pattern:
  rename old table, create new table, copy data, restore indexes, drop old table.
  """

  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    # Prevent SQLite 3.25+ from rewriting FK references in child tables during rename
    execute("PRAGMA legacy_alter_table = ON")
    execute("PRAGMA foreign_keys = OFF")
    execute("ALTER TABLE annotations RENAME TO annotations_old")

    execute("""
    CREATE TABLE annotations (
      id TEXT PRIMARY KEY,
      source TEXT NOT NULL DEFAULT 'terminal',
      relative_path TEXT,
      line_start INTEGER,
      line_end INTEGER,
      metadata TEXT NOT NULL DEFAULT '{}',
      selected_text TEXT NOT NULL,
      start_row INTEGER,
      start_col INTEGER,
      end_row INTEGER,
      end_col INTEGER,
      comment TEXT NOT NULL,
      purpose TEXT NOT NULL DEFAULT 'review',
      state TEXT NOT NULL DEFAULT 'open',
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      session_id TEXT REFERENCES sessions(id),
      subagent_id TEXT REFERENCES subagents(id),
      project_id TEXT REFERENCES projects(id),
      commit_id TEXT REFERENCES commits(id),
      commit_hotspot_id TEXT REFERENCES commit_hotspots(id)
    )
    """)

    execute("""
    INSERT INTO annotations (
      id, source, relative_path, line_start, line_end, metadata,
      selected_text, start_row, start_col, end_row, end_col, comment,
      purpose, state, inserted_at, updated_at,
      session_id, subagent_id, project_id, commit_id, commit_hotspot_id
    )
    SELECT
      id, source, relative_path, line_start, line_end, metadata,
      selected_text, start_row, start_col, end_row, end_col, comment,
      purpose, state, inserted_at, updated_at,
      session_id, subagent_id, project_id, commit_id, commit_hotspot_id
    FROM annotations_old
    """)

    execute("DROP TABLE annotations_old")

    # Restore indexes
    execute("CREATE INDEX annotations_session_id_index ON annotations(session_id)")

    execute("CREATE INDEX annotations_session_id_state_index ON annotations(session_id, state)")
    execute("PRAGMA foreign_keys = ON")
    execute("PRAGMA legacy_alter_table = OFF")
  end

  def down do
    # Revert: make session_id NOT NULL again
    execute("PRAGMA legacy_alter_table = ON")
    execute("PRAGMA foreign_keys = OFF")
    execute("ALTER TABLE annotations RENAME TO annotations_old")

    execute("""
    CREATE TABLE annotations (
      id TEXT PRIMARY KEY,
      source TEXT NOT NULL DEFAULT 'terminal',
      relative_path TEXT,
      line_start INTEGER,
      line_end INTEGER,
      metadata TEXT NOT NULL DEFAULT '{}',
      selected_text TEXT NOT NULL,
      start_row INTEGER,
      start_col INTEGER,
      end_row INTEGER,
      end_col INTEGER,
      comment TEXT NOT NULL,
      purpose TEXT NOT NULL DEFAULT 'review',
      state TEXT NOT NULL DEFAULT 'open',
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      session_id TEXT NOT NULL REFERENCES sessions(id),
      subagent_id TEXT REFERENCES subagents(id),
      project_id TEXT REFERENCES projects(id),
      commit_id TEXT REFERENCES commits(id),
      commit_hotspot_id TEXT REFERENCES commit_hotspots(id)
    )
    """)

    execute("""
    INSERT INTO annotations (
      id, source, relative_path, line_start, line_end, metadata,
      selected_text, start_row, start_col, end_row, end_col, comment,
      purpose, state, inserted_at, updated_at,
      session_id, subagent_id, project_id, commit_id, commit_hotspot_id
    )
    SELECT
      id, source, relative_path, line_start, line_end, metadata,
      selected_text, start_row, start_col, end_row, end_col, comment,
      purpose, state, inserted_at, updated_at,
      session_id, subagent_id, project_id, commit_id, commit_hotspot_id
    FROM annotations_old
    WHERE session_id IS NOT NULL
    """)

    execute("DROP TABLE annotations_old")

    execute("CREATE INDEX annotations_session_id_index ON annotations(session_id)")

    execute("CREATE INDEX annotations_session_id_state_index ON annotations(session_id, state)")
    execute("PRAGMA foreign_keys = ON")
    execute("PRAGMA legacy_alter_table = OFF")
  end
end
