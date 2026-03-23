defmodule Spotter.Repo.Migrations.CreateAnnotationImages do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE annotation_images (
      annotation_id TEXT PRIMARY KEY REFERENCES annotations(id) ON DELETE CASCADE,
      image_data BLOB NOT NULL,
      content_type TEXT NOT NULL DEFAULT 'image/png',
      size_bytes INTEGER NOT NULL,
      inserted_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
    """)
  end

  def down do
    drop(table(:annotation_images))
  end
end
