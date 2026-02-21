defmodule Spotter.Transcripts.CommitHotspot do
  @moduledoc "AI-analyzed code hotspot tied to a specific commit diff."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "commit_hotspots"
    repo Spotter.Repo
  end

  json_api do
    type "commit_hotspot"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :relative_path,
        :line_start,
        :line_end,
        :snippet,
        :reason,
        :overall_score,
        :rubric,
        :model_used,
        :analyzed_at,
        :metadata,
        :symbol_name,
        :project_id,
        :commit_id
      ]

      upsert? true
      upsert_identity :unique_commit_hotspot
    end

    create :mcp_create do
      accept [
        :relative_path,
        :line_start,
        :line_end,
        :snippet,
        :reason,
        :overall_score,
        :rubric,
        :symbol_name,
        :commit_id
      ]

      change fn changeset, _context ->
        case changeset.context[:spotter_mcp_scope] do
          %{project_id: project_id} when is_binary(project_id) ->
            changeset
            |> Ash.Changeset.force_change_attribute(:project_id, project_id)
            |> Ash.Changeset.force_change_attribute(:model_used, "mcp_review")
            |> Ash.Changeset.force_change_attribute(:analyzed_at, DateTime.utc_now())
            |> Ash.Changeset.force_change_attribute(:metadata, %{"source" => "mcp_review"})

          _ ->
            Ash.Changeset.add_error(
              changeset,
              "MCP project scope is required but missing or invalid"
            )
        end
      end

      upsert? true
      upsert_identity :unique_commit_hotspot
    end

    read :mcp_list do
      pagination keyset?: true, required?: false

      prepare fn query, _context ->
        require Ash.Query

        case query.context[:spotter_mcp_scope] do
          %{project_id: project_id} when is_binary(project_id) ->
            Ash.Query.filter(query, project_id == ^project_id)

          _ ->
            Ash.Query.add_error(query, "MCP project scope is required but missing or invalid")
        end
      end
    end

    update :update do
      primary? true

      accept [
        :snippet,
        :reason,
        :overall_score,
        :rubric,
        :model_used,
        :analyzed_at,
        :metadata,
        :symbol_name
      ]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :relative_path, :string, allow_nil?: false
    attribute :line_start, :integer, allow_nil?: false
    attribute :line_end, :integer, allow_nil?: false
    attribute :snippet, :string, allow_nil?: false
    attribute :reason, :string, allow_nil?: false
    attribute :symbol_name, :string

    attribute :overall_score, :float do
      allow_nil? false
      default 0.0
      constraints min: 0.0, max: 100.0
    end

    attribute :rubric, :map do
      allow_nil? false
      default %{}
    end

    attribute :model_used, :string, allow_nil?: false
    attribute :analyzed_at, :utc_datetime_usec, allow_nil?: false

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end

    belongs_to :commit, Spotter.Transcripts.Commit do
      allow_nil? false
    end
  end

  identities do
    identity :unique_commit_hotspot, [
      :commit_id,
      :relative_path,
      :line_start,
      :line_end,
      :symbol_name
    ]
  end
end
