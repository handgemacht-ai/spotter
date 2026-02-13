defmodule Spotter.Transcripts.PromptPatternRun do
  @moduledoc "An analysis run that detects repeated prompt patterns across sessions."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshJsonApi.Resource]

  sqlite do
    table "prompt_pattern_runs"
    repo Spotter.Repo
  end

  json_api do
    type "prompt_pattern_run"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :scope,
        :project_id,
        :timespan_days,
        :prompt_limit,
        :max_prompt_chars,
        :status
      ]
    end

    update :mark_running do
      require_atomic? false
      accept []
      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :complete do
      require_atomic? false
      accept [:prompts_total, :prompts_analyzed, :unique_prompts, :model_used]
      change set_attribute(:status, :completed)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
      change set_attribute(:error, nil)
    end

    update :fail do
      require_atomic? false
      accept [:error]
      change set_attribute(:status, :error)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end
  end

  validations do
    validate fn changeset, _context ->
      scope = Ash.Changeset.get_attribute(changeset, :scope)
      project_id = Ash.Changeset.get_attribute(changeset, :project_id)

      if scope == :project && is_nil(project_id) do
        {:error,
         Ash.Error.Changes.InvalidAttribute.exception(
           field: :project_id,
           message: "must be present when scope is :project"
         )}
      else
        :ok
      end
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :scope, :atom do
      allow_nil? false
      constraints one_of: [:global, :project]
    end

    attribute :timespan_days, :integer, allow_nil?: true
    attribute :prompt_limit, :integer, allow_nil?: false
    attribute :max_prompt_chars, :integer, allow_nil?: false
    attribute :prompts_total, :integer, allow_nil?: false, default: 0
    attribute :prompts_analyzed, :integer, allow_nil?: false, default: 0
    attribute :unique_prompts, :integer, allow_nil?: false, default: 0

    attribute :status, :atom do
      allow_nil? false
      default :queued
      constraints one_of: [:queued, :running, :completed, :error]
    end

    attribute :error, :string, allow_nil?: true
    attribute :model_used, :string, allow_nil?: true
    attribute :started_at, :utc_datetime_usec, allow_nil?: true
    attribute :completed_at, :utc_datetime_usec, allow_nil?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project, allow_nil?: true

    has_many :patterns, Spotter.Transcripts.PromptPattern do
      destination_attribute :run_id
    end
  end
end
