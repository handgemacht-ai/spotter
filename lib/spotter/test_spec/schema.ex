defmodule Spotter.TestSpec.Schema do
  @moduledoc """
  Idempotent DDL for the test specification table in Dolt.

  Called once at application startup when the test spec feature is enabled.
  All statements use `CREATE TABLE IF NOT EXISTS` so they are safe to re-run.
  """

  require Logger

  alias Ecto.Adapters.SQL
  alias Spotter.TestSpec.Repo

  @doc """
  Ensures the `test_specs` table exists in the Dolt database.
  """
  @spec ensure_schema!() :: :ok
  def ensure_schema! do
    case SQL.query(Repo, test_specs_ddl()) do
      {:ok, _} -> :ok
      {:error, %MyXQL.Error{message: msg}} -> Logger.debug("Schema DDL skipped: #{msg}")
    end

    :ok
  end

  defp test_specs_ddl do
    """
    CREATE TABLE IF NOT EXISTS test_specs (
      id BIGINT AUTO_INCREMENT PRIMARY KEY,
      project_id VARCHAR(36) NOT NULL,
      test_key VARCHAR(512) NOT NULL,
      relative_path TEXT NOT NULL,
      framework VARCHAR(64) NOT NULL,
      describe_path_json JSON NOT NULL,
      test_name TEXT NOT NULL,
      line_start INT NULL,
      line_end INT NULL,
      given_json JSON NOT NULL,
      when_json JSON NOT NULL,
      then_json JSON NOT NULL,
      confidence DOUBLE NULL,
      metadata_json JSON NOT NULL,
      source_commit_hash VARCHAR(40) NULL,
      updated_by_git_commit VARCHAR(40) NOT NULL,
      created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
      updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
      UNIQUE KEY uniq_test_specs_project_key (project_id, test_key),
      KEY idx_test_specs_project_path (project_id, relative_path(255))
    )
    """
  end
end
