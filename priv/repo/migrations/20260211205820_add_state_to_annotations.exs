defmodule Spotter.Repo.Migrations.AddStateToAnnotations do
  @moduledoc """
  Adds state column to annotations for open/closed lifecycle.
  """

  use Ecto.Migration

  def up do
    alter table(:annotations) do
      add(:state, :text, null: false, default: "open")
    end

    create index(:annotations, [:session_id, :state], name: "annotations_session_id_state_index")
  end

  def down do
    drop_if_exists(
      index(:annotations, [:session_id, :state], name: "annotations_session_id_state_index")
    )

    alter table(:annotations) do
      remove(:state)
    end
  end
end
