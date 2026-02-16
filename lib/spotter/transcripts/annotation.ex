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
        :purpose
      ]
    end

    update :update do
      primary? true
      accept [:comment, :metadata]
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

      change fn changeset, _context ->
        resolution =
          changeset
          |> Ash.Changeset.get_argument(:resolution)
          |> to_string()
          |> String.trim()

        if resolution == "" do
          Ash.Changeset.add_error(changeset, field: :resolution, message: "must be non-empty")
        else
          kind = Ash.Changeset.get_argument(changeset, :resolution_kind)
          existing = Ash.Changeset.get_data(changeset, :metadata) || %{}

          merged =
            existing
            |> Map.put("resolution", resolution)
            |> Map.put("resolved_at", DateTime.utc_now() |> DateTime.to_iso8601())
            |> then(fn m ->
              if kind, do: Map.put(m, "resolution_kind", Atom.to_string(kind)), else: m
            end)

          Ash.Changeset.change_attribute(changeset, :metadata, merged)
        end
      end
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

      change fn changeset, _context ->
        resolution =
          changeset
          |> Ash.Changeset.get_argument(:resolution)
          |> to_string()
          |> String.trim()

        if resolution == "" do
          Ash.Changeset.add_error(changeset, field: :resolution, message: "must be non-empty")
        else
          kind = Ash.Changeset.get_argument(changeset, :resolution_kind)
          existing = Ash.Changeset.get_data(changeset, :metadata) || %{}

          merged =
            existing
            |> Map.put("resolution", resolution)
            |> Map.put("resolved_at", DateTime.utc_now() |> DateTime.to_iso8601())
            |> then(fn m ->
              if kind, do: Map.put(m, "resolution_kind", Atom.to_string(kind)), else: m
            end)

          Ash.Changeset.change_attribute(changeset, :metadata, merged)
        end
      end
    end
  end

  validations do
    validate fn changeset, _context ->
               source = Ash.Changeset.get_attribute(changeset, :source)
               session_id = Ash.Changeset.get_attribute(changeset, :session_id)

               if source != :file && is_nil(session_id) do
                 {:error, field: :session_id, message: "is required when source is not :file"}
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
      default :terminal
      public? true
      constraints one_of: [:terminal, :transcript, :file, :commit_message, :code, :prompt_pattern]
    end

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
end
