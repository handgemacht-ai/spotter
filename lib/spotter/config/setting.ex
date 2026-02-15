defmodule Spotter.Config.Setting do
  @moduledoc "A persisted configuration override stored in SQLite."
  use Ash.Resource,
    domain: Spotter.Config,
    data_layer: AshSqlite.DataLayer

  @allowed_keys ~w(
    transcripts_dir
    summary_model
    summary_token_budget
    prompt_patterns_max_prompts_per_run
    prompt_patterns_max_prompt_chars
    prompt_patterns_model
    product_spec_system_prompt
    prompt_pattern_system_prompt
    session_distiller_system_prompt
    project_rollup_system_prompt
    waiting_summary_system_prompt
    commit_hotspot_explore_system_prompt
    commit_hotspot_main_system_prompt
    prompt_patterns_sessions_per_run
  )

  sqlite do
    table "config_settings"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:key, :value]

      validate {Spotter.Config.Setting.Validations.AllowedKey, allowed_keys: @allowed_keys}
    end

    update :update do
      primary? true
      accept [:value]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :key, :string do
      allow_nil? false
    end

    attribute :value, :string do
      allow_nil? false
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_key, [:key]
  end
end
