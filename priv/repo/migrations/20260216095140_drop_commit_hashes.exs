defmodule Spotter.Repo.Migrations.DropCommitHashes do
  @moduledoc """
  Removes the unused commit_hashes column from session_distillations.

  Uses table rebuild because SQLite ALTER TABLE DROP COLUMN is unreliable.
  """

  use Ecto.Migration

  def up do
    create table(:session_distillations_new, primary_key: false) do
      add(
        :session_id,
        references(:sessions,
          column: :id,
          name: "session_distillations_session_id_fkey",
          type: :uuid
        ),
        null: false
      )

      add(:updated_at, :utc_datetime_usec, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
      add(:input_stats, :map)
      add(:error_reason, :text)
      add(:raw_response_text, :text)
      add(:summary_text, :text)
      add(:summary_json, :map)
      add(:model_used, :text)
      add(:status, :text, null: false)
      add(:id, :uuid, null: false, primary_key: true)
    end

    execute("""
    INSERT INTO session_distillations_new (
      session_id, updated_at, inserted_at, input_stats, error_reason,
      raw_response_text, summary_text, summary_json, model_used, status, id
    )
    SELECT
      session_id, updated_at, inserted_at, input_stats, error_reason,
      raw_response_text, summary_text, summary_json, model_used, status, id
    FROM session_distillations
    """)

    drop_if_exists(
      unique_index(:session_distillations, [:session_id],
        name: "session_distillations_unique_session_distillation_index"
      )
    )

    drop(table(:session_distillations))

    rename(table(:session_distillations_new), to: table(:session_distillations))

    create unique_index(:session_distillations, [:session_id],
             name: "session_distillations_unique_session_distillation_index"
           )
  end

  def down do
    create table(:session_distillations_old, primary_key: false) do
      add(
        :session_id,
        references(:sessions,
          column: :id,
          name: "session_distillations_session_id_fkey",
          type: :uuid
        ),
        null: false
      )

      add(:updated_at, :utc_datetime_usec, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
      add(:input_stats, :map)
      add(:commit_hashes, {:array, :text}, null: false, default: [])
      add(:error_reason, :text)
      add(:raw_response_text, :text)
      add(:summary_text, :text)
      add(:summary_json, :map)
      add(:model_used, :text)
      add(:status, :text, null: false)
      add(:id, :uuid, null: false, primary_key: true)
    end

    execute("""
    INSERT INTO session_distillations_old (
      session_id, updated_at, inserted_at, input_stats, commit_hashes, error_reason,
      raw_response_text, summary_text, summary_json, model_used, status, id
    )
    SELECT
      session_id, updated_at, inserted_at, input_stats, '[]', error_reason,
      raw_response_text, summary_text, summary_json, model_used, status, id
    FROM session_distillations
    """)

    drop_if_exists(
      unique_index(:session_distillations, [:session_id],
        name: "session_distillations_unique_session_distillation_index"
      )
    )

    drop(table(:session_distillations))

    rename(table(:session_distillations_old), to: table(:session_distillations))

    create unique_index(:session_distillations, [:session_id],
             name: "session_distillations_unique_session_distillation_index"
           )
  end
end
