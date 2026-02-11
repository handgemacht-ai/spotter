defmodule Spotter.Transcripts.FileSnapshot do
  @moduledoc false

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "file_snapshots"
    repo Spotter.Repo
  end

  json_api do
    type "file_snapshot"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :tool_use_id,
        :file_path,
        :relative_path,
        :content_before,
        :content_after,
        :change_type,
        :source,
        :timestamp,
        :session_id
      ]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :tool_use_id, :string, allow_nil?: false
    attribute :file_path, :string, allow_nil?: false
    attribute :relative_path, :string
    attribute :content_before, :string
    attribute :content_after, :string

    attribute :change_type, :atom do
      allow_nil? false
      constraints one_of: [:created, :modified, :deleted]
    end

    attribute :source, :atom do
      allow_nil? false
      constraints one_of: [:write, :edit, :bash]
    end

    attribute :timestamp, :utc_datetime_usec, allow_nil?: false

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end
  end
end
