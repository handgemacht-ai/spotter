defmodule Spotter.TestSpec.Schema do
  @moduledoc """
  Idempotent DDL for the test specification table in Dolt.

  Called once at application startup when the test spec feature is enabled.
  All statements use `CREATE TABLE IF NOT EXISTS` so they are safe to re-run.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Ecto.Adapters.SQL
  alias Spotter.TestSpec.Repo

  @db_name_pattern ~r/\A[a-zA-Z0-9_]+\z/

  @doc """
  Ensures the configured Dolt database exists, creating it if necessary.

  Uses a direct MyXQL connection (without selecting a database) to execute
  `CREATE DATABASE IF NOT EXISTS`. Fails safely — logs warnings and returns
  `:ok` on any error so startup is never blocked.
  """
  @spec ensure_database!() :: :ok
  def ensure_database! do
    Tracer.with_span "spotter.test_spec.schema.ensure_database" do
      repo_config = Application.fetch_env!(:spotter, Spotter.TestSpec.Repo)
      db_name = Keyword.fetch!(repo_config, :database)

      Tracer.set_attribute("spotter.test_spec.database", db_name)

      if Regex.match?(@db_name_pattern, db_name) do
        do_ensure_database(repo_config, db_name)
      else
        Logger.warning("TestSpec DB bootstrap skipped: invalid database name #{inspect(db_name)}")

        Tracer.set_attribute("spotter.test_spec.db_ensure_result", "skipped_invalid_name")
        :ok
      end
    end
  end

  @doc """
  Ensures the `test_specs` table exists in the Dolt database.
  """
  @spec ensure_schema!() :: :ok
  def ensure_schema! do
    ensure_database!()

    case SQL.query(Repo, test_specs_ddl()) do
      {:ok, _} -> :ok
      {:error, %MyXQL.Error{message: msg}} -> Logger.debug("Schema DDL skipped: #{msg}")
    end

    :ok
  end

  defp do_ensure_database(repo_config, db_name) do
    conn_opts = [
      hostname: Keyword.get(repo_config, :hostname, "localhost"),
      port: Keyword.get(repo_config, :port, 3306),
      username: Keyword.get(repo_config, :username),
      password: Keyword.get(repo_config, :password),
      database: nil
    ]

    case MyXQL.start_link(conn_opts) do
      {:ok, conn} ->
        try do
          case MyXQL.query(conn, "CREATE DATABASE IF NOT EXISTS `#{db_name}`") do
            {:ok, _} ->
              Tracer.set_attribute(
                "spotter.test_spec.db_ensure_result",
                "created_or_exists"
              )

              :ok

            {:error, %MyXQL.Error{message: msg}} ->
              Logger.warning("TestSpec DB bootstrap CREATE failed: #{msg}")
              Tracer.set_attribute("spotter.test_spec.db_ensure_result", "skipped_error")
              Tracer.set_status(:error, msg)
              :ok
          end
        after
          GenServer.stop(conn)
        end

      {:error, reason} ->
        Logger.warning(
          "TestSpec DB bootstrap connection failed for #{db_name}: #{inspect(reason)}"
        )

        Tracer.set_attribute("spotter.test_spec.db_ensure_result", "skipped_error")
        Tracer.set_status(:error, inspect(reason))
        :ok
    end
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
