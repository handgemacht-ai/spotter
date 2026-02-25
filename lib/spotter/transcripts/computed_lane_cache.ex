defmodule Spotter.Transcripts.ComputedLaneCache do
  @moduledoc """
  Persisted cache of pre-computed lane data for team parallel transcript views.

  Stores the serialized output of `ParallelLanes.compute/1` so that opening
  lanes is an instant DB read instead of an expensive re-computation.
  Populated by the `ComputeLanes` Oban worker after transcript sync.
  """

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "computed_lane_caches"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :upsert do
      primary? true
      accept [:team_id, :payload, :version, :computed_at]
      upsert? true
      upsert_identity :unique_team
      upsert_fields [:payload, :version, :computed_at, :updated_at]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :payload, :binary do
      allow_nil? false
      description "Erlang term_to_binary of the computed lanes result map."
    end

    attribute :version, :integer do
      allow_nil? false
      default 1
      description "Schema version for forward-compatible deserialization."
    end

    attribute :computed_at, :utc_datetime_usec do
      allow_nil? false
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :team, Spotter.Transcripts.Team do
      allow_nil? false
    end
  end

  identities do
    identity :unique_team, [:team_id]
  end
end
