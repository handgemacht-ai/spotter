defmodule Spotter.Repo.Migrations.AddSearchDocumentsAndFts5 do
  @moduledoc """
  Creates the search_documents table and best-effort FTS5 virtual table + triggers.
  The migration always succeeds even if FTS5 is unavailable.
  """

  use Ecto.Migration

  def up do
    create table(:search_documents, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:project_id, :uuid, null: false)
      add(:kind, :text, null: false)
      add(:external_id, :text, null: false)
      add(:title, :text, null: false)
      add(:subtitle, :text)
      add(:url, :text, null: false)
      add(:search_text, :text, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :search_documents,
             [:project_id, :kind, :external_id],
             name: :search_documents_unique_project_kind_external_index
           )

    # FTS5 objects are best-effort: if FTS5 is not available, the migration
    # continues and the query layer falls back to LIKE.
    try do
      execute("""
      CREATE VIRTUAL TABLE search_documents_fts USING fts5(
        title,
        subtitle,
        search_text,
        kind,
        project_id,
        external_id,
        content='search_documents',
        content_rowid='rowid',
        tokenize='unicode61'
      );
      """)

      execute("""
      CREATE TRIGGER search_documents_ai AFTER INSERT ON search_documents BEGIN
        INSERT INTO search_documents_fts(rowid, title, subtitle, search_text, kind, project_id, external_id)
        VALUES (new.rowid, new.title, new.subtitle, new.search_text, new.kind, new.project_id, new.external_id);
      END;
      """)

      execute("""
      CREATE TRIGGER search_documents_ad AFTER DELETE ON search_documents BEGIN
        INSERT INTO search_documents_fts(search_documents_fts, rowid, title, subtitle, search_text, kind, project_id, external_id)
        VALUES ('delete', old.rowid, old.title, old.subtitle, old.search_text, old.kind, old.project_id, old.external_id);
      END;
      """)

      execute("""
      CREATE TRIGGER search_documents_au AFTER UPDATE ON search_documents BEGIN
        INSERT INTO search_documents_fts(search_documents_fts, rowid, title, subtitle, search_text, kind, project_id, external_id)
        VALUES ('delete', old.rowid, old.title, old.subtitle, old.search_text, old.kind, old.project_id, old.external_id);
        INSERT INTO search_documents_fts(rowid, title, subtitle, search_text, kind, project_id, external_id)
        VALUES (new.rowid, new.title, new.subtitle, new.search_text, new.kind, new.project_id, new.external_id);
      END;
      """)
    rescue
      _ -> :ok
    end
  end

  def down do
    execute("DROP TRIGGER IF EXISTS search_documents_au;")
    execute("DROP TRIGGER IF EXISTS search_documents_ad;")
    execute("DROP TRIGGER IF EXISTS search_documents_ai;")
    execute("DROP TABLE IF EXISTS search_documents_fts;")
    drop(table(:search_documents))
  end
end
