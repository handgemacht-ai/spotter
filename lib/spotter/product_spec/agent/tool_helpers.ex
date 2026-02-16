defmodule Spotter.ProductSpec.Agent.ToolHelpers do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias Spotter.Observability.AgentRunScope
  alias Spotter.ProductSpec.Repo

  @spec_key_re ~r/^[a-z0-9][a-z0-9-]{2,159}$/
  @uuid_re ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  @doc "Sets the project_id for the current spec agent run (transitional fallback)."
  @spec set_project_id(String.t() | nil) :: :ok
  def set_project_id(nil) do
    Process.delete(:spec_agent_project_id)
    :ok
  end

  def set_project_id(id) when is_binary(id) do
    Process.put(:spec_agent_project_id, id)
    :ok
  end

  @doc "Returns the bound project_id, or nil if not set."
  @spec project_id() :: String.t() | nil
  def project_id do
    case AgentRunScope.resolve_for_current_process() do
      {:ok, %{project_id: id}} when is_binary(id) -> id
      _ -> Process.get(:spec_agent_project_id)
    end
  end

  @doc "Returns the bound project_id or raises if not set or invalid."
  @spec project_id!() :: String.t()
  def project_id! do
    id = project_id()

    case id do
      nil ->
        raise "spec_agent_project_id not bound — scope not available via AgentRunScope or process dictionary"

      id when is_binary(id) ->
        unless Regex.match?(@uuid_re, id) do
          raise "spec_agent_project_id is not a valid UUID: #{inspect(id)}"
        end

        id
    end
  end

  @doc "Sets the git commit hash used by write tools for `updated_by_git_commit` (transitional fallback)."
  @spec set_commit_hash(String.t()) :: :ok
  def set_commit_hash(hash) do
    Process.put(:spec_agent_commit_hash, hash)
    :ok
  end

  def commit_hash do
    case AgentRunScope.resolve_for_current_process() do
      {:ok, %{commit_hash: hash}} when is_binary(hash) -> hash
      _ -> Process.get(:spec_agent_commit_hash, "")
    end
  end

  @doc "Sets the git working directory for repo inspection tools (transitional fallback)."
  @spec set_git_cwd(String.t() | nil) :: :ok
  def set_git_cwd(cwd) do
    Process.put(:spec_agent_git_cwd, cwd)
    :ok
  end

  def git_cwd do
    case AgentRunScope.resolve_for_current_process() do
      {:ok, %{git_cwd: cwd}} when is_binary(cwd) -> cwd
      _ -> Process.get(:spec_agent_git_cwd)
    end
  end

  def text_result(data) do
    {:ok, %{"content" => [%{"type" => "text", "text" => Jason.encode!(data)}]}}
  end

  def validate_spec_key(key) do
    if Regex.match?(@spec_key_re, key),
      do: :ok,
      else: {:error, "spec_key must match ^[a-z0-9][a-z0-9-]{2,159}$"}
  end

  def maybe_validate_spec_key(nil), do: :ok
  def maybe_validate_spec_key(key), do: validate_spec_key(key)

  def validate_shall(statement) do
    if statement =~ ~r/shall/i,
      do: :ok,
      else: {:error, "statement must include 'shall'"}
  end

  def maybe_validate_shall(nil), do: :ok
  def maybe_validate_shall(statement), do: validate_shall(statement)

  def rows_to_maps(%{columns: columns, rows: rows}) do
    Enum.map(rows, fn row ->
      columns |> Enum.zip(row) |> Map.new()
    end)
  end

  def build_update_sets(input, fields) do
    Enum.reduce(fields, {[], []}, fn field, {sets, params} ->
      case input[field] do
        nil -> {sets, params}
        value -> {sets ++ ["#{field} = ?"], params ++ [value]}
      end
    end)
  end

  def dolt_query!(sql, params \\ []) do
    SQL.query!(Repo, sql, params)
  end

  @doc "Validates a list of evidence file paths. Returns :ok or {:error, reason}."
  @spec validate_evidence_files([term()]) :: :ok | {:error, String.t()}
  def validate_evidence_files(files) when is_list(files) do
    invalid =
      Enum.reject(files, fn f ->
        is_binary(f) and f != "" and
          not String.starts_with?(f, "/") and
          not String.contains?(f, "..") and
          not String.contains?(f, "\\")
      end)

    case invalid do
      [] -> :ok
      _ -> {:error, "invalid evidence file paths: #{inspect(invalid)}"}
    end
  end

  def validate_evidence_files(_), do: {:error, "evidence_files must be a list of strings"}

  @doc "Verifies that domain_id belongs to the given project_id."
  @spec verify_domain_belongs_to_project(String.t(), String.t()) :: :ok | {:error, String.t()}
  def verify_domain_belongs_to_project(domain_id, project_id) do
    result =
      dolt_query!(
        "SELECT COUNT(*) FROM product_domains WHERE id = ? AND project_id = ?",
        [domain_id, project_id]
      )

    case result.rows do
      [[n]] when n > 0 -> :ok
      _ -> {:error, "domain #{domain_id} does not belong to project #{project_id}"}
    end
  end

  @doc "Verifies that feature_id belongs to the given project_id."
  @spec verify_feature_belongs_to_project(String.t(), String.t()) :: :ok | {:error, String.t()}
  def verify_feature_belongs_to_project(feature_id, project_id) do
    result =
      dolt_query!(
        "SELECT COUNT(*) FROM product_features WHERE id = ? AND project_id = ?",
        [feature_id, project_id]
      )

    case result.rows do
      [[n]] when n > 0 -> :ok
      _ -> {:error, "feature #{feature_id} does not belong to project #{project_id}"}
    end
  end
end
