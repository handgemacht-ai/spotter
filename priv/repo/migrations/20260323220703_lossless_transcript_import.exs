defmodule Spotter.Repo.Migrations.LosslessTranscriptImport do
  @moduledoc """
  Makes uuid/timestamp nullable on messages, adds lossless import columns.

  SQLite cannot ALTER COLUMN nullability, so we use the table-rewrite pattern.
  """

  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    execute("PRAGMA legacy_alter_table = ON")
    execute("PRAGMA foreign_keys = OFF")
    execute("ALTER TABLE messages RENAME TO messages_old")

    execute("""
    CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      uuid TEXT,
      parent_uuid TEXT,
      message_id TEXT,
      type TEXT NOT NULL,
      role TEXT,
      content TEXT,
      raw_payload TEXT,
      timestamp TEXT,
      is_sidechain INTEGER,
      agent_id TEXT,
      tool_use_id TEXT,
      ordinal INTEGER,
      source_scope TEXT,
      record_type TEXT,
      record_subtype TEXT,
      normalization_status TEXT,
      parent_tool_use_id TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      session_id TEXT NOT NULL REFERENCES sessions(id),
      subagent_id TEXT REFERENCES subagents(id)
    )
    """)

    execute("""
    INSERT INTO messages (
      id, uuid, parent_uuid, message_id, type, role, content, raw_payload,
      timestamp, is_sidechain, agent_id, tool_use_id,
      inserted_at, updated_at, session_id, subagent_id
    )
    SELECT
      id, uuid, parent_uuid, message_id, type, role, content, raw_payload,
      timestamp, is_sidechain, agent_id, tool_use_id,
      inserted_at, updated_at, session_id, subagent_id
    FROM messages_old
    """)

    execute("DROP TABLE messages_old")

    create unique_index(:messages, [:session_id, :uuid],
             name: "messages_unique_session_uuid_index"
           )

    create unique_index(:messages, [:session_id, :source_scope, :ordinal],
             name: "messages_unique_session_scope_ordinal_index"
           )

    execute("PRAGMA foreign_keys = ON")
    execute("PRAGMA legacy_alter_table = OFF")
  end

  def down do
    execute("PRAGMA legacy_alter_table = ON")
    execute("PRAGMA foreign_keys = OFF")

    drop_if_exists(
      unique_index(:messages, [:session_id, :source_scope, :ordinal],
        name: "messages_unique_session_scope_ordinal_index"
      )
    )

    drop_if_exists(
      unique_index(:messages, [:session_id, :uuid], name: "messages_unique_session_uuid_index")
    )

    execute("ALTER TABLE messages RENAME TO messages_old")

    execute("""
    CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      uuid TEXT NOT NULL,
      parent_uuid TEXT,
      message_id TEXT,
      type TEXT NOT NULL,
      role TEXT,
      content TEXT,
      raw_payload TEXT,
      timestamp TEXT NOT NULL,
      is_sidechain INTEGER,
      agent_id TEXT,
      tool_use_id TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      session_id TEXT NOT NULL REFERENCES sessions(id),
      subagent_id TEXT REFERENCES subagents(id)
    )
    """)

    execute("""
    INSERT INTO messages (
      id, uuid, parent_uuid, message_id, type, role, content, raw_payload,
      timestamp, is_sidechain, agent_id, tool_use_id,
      inserted_at, updated_at, session_id, subagent_id
    )
    SELECT
      id, uuid, parent_uuid, message_id, type, role, content, raw_payload,
      timestamp, is_sidechain, agent_id, tool_use_id,
      inserted_at, updated_at, session_id, subagent_id
    FROM messages_old
    WHERE uuid IS NOT NULL AND timestamp IS NOT NULL
    """)

    execute("DROP TABLE messages_old")

    create unique_index(:messages, [:session_id, :uuid],
             name: "messages_unique_session_uuid_index"
           )

    execute("PRAGMA foreign_keys = ON")
    execute("PRAGMA legacy_alter_table = OFF")
  end
end
