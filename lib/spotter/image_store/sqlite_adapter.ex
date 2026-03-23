defmodule Spotter.ImageStore.SqliteAdapter do
  @moduledoc false
  @behaviour Spotter.ImageStore

  alias Ecto.Adapters.SQL

  @max_size_bytes 5 * 1024 * 1024

  @impl true
  def store(image_binary, annotation_id)
      when is_binary(image_binary) and is_binary(annotation_id) do
    size = byte_size(image_binary)

    if size > @max_size_bytes do
      {:error, :too_large}
    else
      SQL.query(
        Spotter.Repo,
        """
        INSERT INTO annotation_images (annotation_id, image_data, content_type, size_bytes, inserted_at)
        VALUES (?1, ?2, ?3, ?4, datetime('now'))
        ON CONFLICT (annotation_id) DO UPDATE SET
          image_data = excluded.image_data,
          content_type = excluded.content_type,
          size_bytes = excluded.size_bytes,
          inserted_at = excluded.inserted_at
        """,
        [annotation_id, image_binary, "image/png", size]
      )
      |> case do
        {:ok, _} -> {:ok, annotation_id}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl true
  def fetch(reference) when is_binary(reference) do
    SQL.query(
      Spotter.Repo,
      "SELECT image_data FROM annotation_images WHERE annotation_id = ?1",
      [reference]
    )
    |> case do
      {:ok, %{rows: [[image_data]]}} -> {:ok, image_data}
      {:ok, %{rows: []}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(reference) when is_binary(reference) do
    SQL.query(
      Spotter.Repo,
      "DELETE FROM annotation_images WHERE annotation_id = ?1",
      [reference]
    )
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
