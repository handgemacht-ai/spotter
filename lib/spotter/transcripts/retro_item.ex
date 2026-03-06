defmodule Spotter.Transcripts.RetroItem do
  @moduledoc "Individual observation within a retrospective submission."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "retro_items"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :category,
        :observation,
        :explanation,
        :rating,
        :retro_submission_id
      ]
    end

    update :rate do
      accept []
      require_atomic? false

      argument :rating, :atom do
        allow_nil? false
        constraints one_of: [:useful, :undecided, :not_useful]
      end

      change set_attribute(:rating, arg(:rating))
    end

    update :mcp_rate do
      accept []
      require_atomic? false

      argument :rating, :atom do
        allow_nil? false
        constraints one_of: [:useful, :undecided, :not_useful]
      end

      change fn changeset, _context ->
        with %{project_id: project_id} when is_binary(project_id) <-
               changeset.context[:spotter_mcp_scope],
             {:ok, submission} <-
               Ash.get(Spotter.Transcripts.RetroSubmission, changeset.data.retro_submission_id),
             true <- submission.project_id == project_id do
          changeset
        else
          _ ->
            Ash.Changeset.add_error(
              changeset,
              "MCP project scope is required and must match retro item project"
            )
        end
      end

      change set_attribute(:rating, arg(:rating))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :category, :atom do
      allow_nil? false

      constraints one_of: [
                    :knowledge_gained,
                    :effective_strategy,
                    :gotcha,
                    :requirements_clarity,
                    :struggle
                  ]
    end

    attribute :observation, :string, allow_nil?: false
    attribute :explanation, :string, allow_nil?: false

    attribute :rating, :atom do
      default :undecided
      constraints one_of: [:useful, :undecided, :not_useful]
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :retro_submission, Spotter.Transcripts.RetroSubmission do
      allow_nil? false
    end

    has_one :session, Spotter.Transcripts.Session do
      manual Spotter.Transcripts.RetroItem.Relationships.SessionThrough
    end
  end
end
