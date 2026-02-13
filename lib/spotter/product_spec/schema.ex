defmodule Spotter.ProductSpec.Schema do
  @moduledoc """
  Idempotent DDL for the product specification tables in Dolt.

  Called once at application startup when the product spec feature is enabled.
  All statements use `CREATE TABLE IF NOT EXISTS` so they are safe to re-run.
  """

  require Logger

  alias Ecto.Adapters.SQL
  alias Spotter.ProductSpec.Repo

  @doc """
  Ensures the product_domains, product_features, and product_requirements
  tables exist in the Dolt database.
  """
  @spec ensure_schema!() :: :ok
  def ensure_schema! do
    for sql <- [domains_ddl(), features_ddl(), requirements_ddl()] do
      case SQL.query(Repo, sql) do
        {:ok, _} -> :ok
        # Dolt raises "already exists" for indexes even with IF NOT EXISTS
        {:error, %MyXQL.Error{message: msg}} -> Logger.debug("Schema DDL skipped: #{msg}")
      end
    end

    ensure_column!("product_requirements", "evidence_files", "JSON NULL")

    :ok
  end

  defp domains_ddl do
    """
    CREATE TABLE IF NOT EXISTS product_domains (
      id CHAR(36) NOT NULL PRIMARY KEY,
      project_id CHAR(36) NOT NULL,
      spec_key VARCHAR(120) NOT NULL,
      name VARCHAR(255) NOT NULL,
      description TEXT NULL,
      updated_by_git_commit CHAR(40) NULL,
      inserted_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
      updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
      UNIQUE KEY uniq_domains_project_key (project_id, spec_key),
      KEY idx_domains_project (project_id)
    )
    """
  end

  defp features_ddl do
    """
    CREATE TABLE IF NOT EXISTS product_features (
      id CHAR(36) NOT NULL PRIMARY KEY,
      project_id CHAR(36) NOT NULL,
      domain_id CHAR(36) NOT NULL,
      spec_key VARCHAR(120) NOT NULL,
      name VARCHAR(255) NOT NULL,
      description TEXT NULL,
      updated_by_git_commit CHAR(40) NULL,
      inserted_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
      updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
      UNIQUE KEY uniq_features_domain_key (project_id, domain_id, spec_key),
      KEY idx_features_domain (project_id, domain_id)
    )
    """
  end

  defp ensure_column!(table, column, type) do
    case SQL.query(Repo, "SHOW COLUMNS FROM #{table} LIKE '#{column}'") do
      {:ok, %{num_rows: 0}} ->
        case SQL.query(Repo, "ALTER TABLE #{table} ADD COLUMN #{column} #{type}") do
          {:ok, _} -> :ok
          {:error, %MyXQL.Error{message: msg}} -> Logger.debug("Column ensure skipped: #{msg}")
        end

      {:ok, _} ->
        :ok
    end
  end

  defp requirements_ddl do
    """
    CREATE TABLE IF NOT EXISTS product_requirements (
      id CHAR(36) NOT NULL PRIMARY KEY,
      project_id CHAR(36) NOT NULL,
      feature_id CHAR(36) NOT NULL,
      spec_key VARCHAR(160) NOT NULL,
      statement TEXT NOT NULL,
      rationale TEXT NULL,
      acceptance_criteria JSON NULL,
      priority VARCHAR(20) NULL,
      updated_by_git_commit CHAR(40) NULL,
      inserted_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
      updated_at TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
      UNIQUE KEY uniq_requirements_feature_key (project_id, feature_id, spec_key),
      KEY idx_requirements_feature (project_id, feature_id)
    )
    """
  end
end
