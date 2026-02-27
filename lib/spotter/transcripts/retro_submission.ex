defmodule Spotter.Transcripts.RetroSubmission do
  @moduledoc "Header record for one agent self-report retrospective."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  sqlite do
    table "retro_submissions"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :summary,
        :submitted_at,
        :session_id,
        :project_id
      ]
    end

    create :mcp_submit do
      accept [:summary]

      argument :session_id, :string do
        allow_nil? false
      end

      argument :items, {:array, :map} do
        allow_nil? false
        constraints min_length: 1
      end

      change fn changeset, _context ->
        case changeset.context[:spotter_mcp_scope] do
          %{project_id: project_id} when is_binary(project_id) ->
            claude_session_id = Ash.Changeset.get_argument(changeset, :session_id)

            case Spotter.Transcripts.Session
                 |> Ash.Query.filter(session_id == ^claude_session_id)
                 |> Ash.read_one() do
              {:ok, %{id: id, project_id: ^project_id}} ->
                changeset
                |> Ash.Changeset.force_change_attribute(:session_id, id)
                |> Ash.Changeset.force_change_attribute(:project_id, project_id)
                |> Ash.Changeset.force_change_attribute(:submitted_at, DateTime.utc_now())

              _ ->
                Ash.Changeset.add_error(
                  changeset,
                  "session_id does not belong to MCP scoped project"
                )
            end

          _ ->
            Ash.Changeset.add_error(
              changeset,
              "MCP project scope is required but missing or invalid"
            )
        end
      end

      change after_action(fn changeset, submission, _context ->
               items = Ash.Changeset.get_argument(changeset, :items)

               Tracer.with_span "spotter.retro.submit_items" do
                 Tracer.set_attribute(:"retro.item_count", length(items))

                 try do
                   Enum.each(items, fn item ->
                     Ash.create!(Spotter.Transcripts.RetroItem, %{
                       retro_submission_id: submission.id,
                       category: item["category"],
                       observation: item["observation"],
                       explanation: item["explanation"]
                     })
                   end)
                 rescue
                   error ->
                     Tracer.set_status(:error, Exception.message(error))
                     reraise error, __STACKTRACE__
                 end
               end

               {:ok, submission}
             end)
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
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :summary, :string
    attribute :submitted_at, :utc_datetime_usec, allow_nil?: false

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end

    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end

    has_many :items, Spotter.Transcripts.RetroItem
  end
end
