defmodule Spotter.Transcripts.Annotation do
  @moduledoc false
  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "annotations"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :read_review_annotations do
      filter expr(purpose == :review)
    end

    read :mcp_read_review_annotations do
      filter expr(purpose == :review)

      argument :bead_id, :string, allow_nil?: true

      prepare fn query, _context ->
        require Ash.Query

        case query.context[:spotter_mcp_scope] do
          %{project_id: project_id} = scope when is_binary(project_id) ->
            query = Ash.Query.filter(query, project_id == ^project_id)

            query =
              case query.arguments[:bead_id] do
                nil -> query
                bead_id -> Ash.Query.filter(query, bead_id == ^bead_id)
              end

            case scope[:worktree_name] do
              nil ->
                query

              wt_name ->
                Ash.Query.filter(
                  query,
                  fragment(
                    "json_extract(?, '$.worktree_name') = ? OR json_extract(?, '$.worktree_name') IS NULL",
                    metadata,
                    ^wt_name,
                    metadata
                  )
                )
            end

          _ ->
            Ash.Query.add_error(query, "MCP project scope is required but missing or invalid")
        end
      end
    end

    read :rest_list do
      argument :project_id, :uuid, allow_nil?: true
      argument :bead_id, :string, allow_nil?: true

      filter expr(purpose == :review and state == :open)

      prepare fn query, _context ->
        require Ash.Query

        query =
          case Ash.Query.get_argument(query, :project_id) do
            nil -> query
            pid -> Ash.Query.filter(query, project_id == ^pid)
          end

        case Ash.Query.get_argument(query, :bead_id) do
          nil -> query
          bid -> Ash.Query.filter(query, bead_id == ^bid)
        end
      end
    end

    read :list_for_bead do
      argument :bead_id, :string, allow_nil?: false

      filter expr(
               source in [:plan, :product_feedback] and state == :open and
                 bead_id == ^arg(:bead_id)
             )
    end

    create :create do
      primary? true

      accept [
        :session_id,
        :subagent_id,
        :selected_text,
        :start_row,
        :start_col,
        :end_row,
        :end_col,
        :comment,
        :source,
        :state,
        :relative_path,
        :line_start,
        :line_end,
        :metadata,
        :project_id,
        :commit_id,
        :commit_hotspot_id,
        :purpose,
        :bead_id,
        :image_ref
      ]
    end

    update :update do
      primary? true
      accept [:comment, :metadata, :image_ref]
    end

    update :close do
      accept []
      change set_attribute(:state, :closed)
    end

    update :resolve do
      accept []
      require_atomic? false

      argument :resolution, :string, allow_nil?: false

      argument :resolution_kind, :atom,
        allow_nil?: true,
        constraints: [
          one_of: [:code_change, :process_change, :tooling_change, :doc_change, :wont_fix]
        ]

      change set_attribute(:state, :closed)
      change Spotter.Transcripts.Changes.ApplyResolution
    end

    update :mcp_resolve do
      accept []
      require_atomic? false

      argument :resolution, :string, allow_nil?: false

      argument :resolution_kind, :atom,
        allow_nil?: true,
        constraints: [
          one_of: [:code_change, :process_change, :tooling_change, :doc_change, :wont_fix]
        ]

      validate fn changeset, _context ->
        scope = changeset.context[:spotter_mcp_scope]
        annotation_project_id = Ash.Changeset.get_data(changeset, :project_id)

        cond do
          is_nil(scope) or not is_map(scope) ->
            {:error, "MCP project scope is required but missing or invalid"}

          is_nil(annotation_project_id) ->
            :ok

          to_string(annotation_project_id) != to_string(scope.project_id) ->
            {:error, "annotation belongs to a different project than the MCP scope"}

          true ->
            :ok
        end
      end

      change set_attribute(:state, :closed)
      change Spotter.Transcripts.Changes.ApplyResolution
    end
  end

  validations do
    validate fn changeset, _context ->
               source = Ash.Changeset.get_attribute(changeset, :source)
               session_id = Ash.Changeset.get_attribute(changeset, :session_id)

               if source not in [:file, :plan, :product_feedback] && is_nil(session_id) do
                 {:error,
                  field: :session_id,
                  message: "is required when source is not :file, :plan, or :product_feedback"}
               else
                 :ok
               end
             end,
             on: [:create]
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :source, :atom do
      allow_nil? false
      default :transcript
      public? true

      constraints one_of: [
                    :terminal,
                    :transcript,
                    :file,
                    :commit_message,
                    :code,
                    :prompt_pattern,
                    :plan,
                    :product_feedback
                  ]
    end

    attribute :bead_id, :string, public?: true
    attribute :image_ref, :string, public?: true
    attribute :relative_path, :string
    attribute :line_start, :integer
    attribute :line_end, :integer

    attribute :metadata, :map do
      allow_nil? false
      default %{}
    end

    attribute :selected_text, :string, allow_nil?: false, public?: true
    attribute :start_row, :integer, allow_nil?: true
    attribute :start_col, :integer, allow_nil?: true
    attribute :end_row, :integer, allow_nil?: true
    attribute :end_col, :integer, allow_nil?: true
    attribute :comment, :string, allow_nil?: false, public?: true

    attribute :purpose, :atom do
      allow_nil? false
      default :review
      public? true
      constraints one_of: [:review, :explain]
    end

    attribute :state, :atom do
      allow_nil? false
      default :open
      public? true
      constraints one_of: [:open, :closed]
    end

    create_timestamp :inserted_at, public?: true
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? true
      attribute_public? true
    end

    belongs_to :subagent, Spotter.Transcripts.Subagent do
      allow_nil? true
      attribute_public? true
    end

    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? true
    end

    belongs_to :commit, Spotter.Transcripts.Commit do
      allow_nil? true
    end

    belongs_to :commit_hotspot, Spotter.Transcripts.CommitHotspot do
      allow_nil? true
    end

    has_many :message_refs, Spotter.Transcripts.AnnotationMessageRef
    has_many :file_refs, Spotter.Transcripts.AnnotationFileRef
  end

  calculations do
    calculate :has_image, :boolean, expr(not is_nil(image_ref))
  end
end
