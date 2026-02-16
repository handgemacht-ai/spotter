defmodule Spotter.Transcripts.SessionCommitLink do
  @moduledoc "Links a session to a commit with type and confidence."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  require OpenTelemetry.Tracer, as: Tracer

  sqlite do
    table "session_commit_links"
    repo Spotter.Repo
  end

  json_api do
    type "session_commit_link"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :link_type,
        :confidence,
        :evidence,
        :session_id,
        :commit_id
      ]

      upsert? true
      upsert_identity :unique_session_commit_link_type
      upsert_fields [:confidence, :evidence]

      change after_action(&maybe_retrigger_distillation/3)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :link_type, :atom do
      allow_nil? false

      constraints one_of: [
                    :observed_in_session,
                    :descendant_of_observed,
                    :patch_match,
                    :file_overlap
                  ]
    end

    attribute :confidence, :float do
      allow_nil? false
      constraints min: 0.0, max: 1.0
    end

    attribute :evidence, :map

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :session, Spotter.Transcripts.Session do
      allow_nil? false
    end

    belongs_to :commit, Spotter.Transcripts.Commit do
      allow_nil? false
    end
  end

  identities do
    identity :unique_session_commit_link_type, [:session_id, :commit_id, :link_type]
  end

  require Ash.Query

  alias Spotter.Transcripts.Jobs.DistillCompletedSession
  alias Spotter.Transcripts.{Session, SessionDistillation}

  defp maybe_retrigger_distillation(_changeset, link, _context) do
    Tracer.with_span "spotter.session_commit_link.retrigger_distillation" do
      Tracer.set_attribute("spotter.session_id", to_string(link.session_id))
      Tracer.set_attribute("spotter.commit_id", to_string(link.commit_id))
      Tracer.set_attribute("spotter.link_type", to_string(link.link_type))
      Tracer.set_attribute("spotter.confidence", link.confidence)

      session = Ash.get!(Session, link.session_id)

      if is_nil(session.hook_ended_at) do
        {:ok, link}
      else
        distillation =
          SessionDistillation
          |> Ash.Query.filter(session_id == ^session.id)
          |> Ash.read_one!()

        if distillation && distillation.status == :skipped &&
             distillation.error_reason == "no_commit_links" do
          trace_ctx = Spotter.Telemetry.TraceContext

          %{
            session_id: to_string(session.session_id),
            otel_trace_id: trace_ctx.current_trace_id(),
            otel_traceparent: trace_ctx.current_traceparent()
          }
          |> DistillCompletedSession.new()
          |> Oban.insert()
        end

        {:ok, link}
      end
    end
  rescue
    error ->
      require Logger
      Logger.warning("SessionCommitLink retrigger failed: #{inspect(error)}")
      {:ok, link}
  end
end
