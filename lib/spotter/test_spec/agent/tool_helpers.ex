defmodule Spotter.TestSpec.Agent.ToolHelpers do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias Spotter.Observability.AgentRunScope
  alias Spotter.TestSpec.Repo

  @uuid_re ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  # -- Process-dictionary scope binding (transitional fallback) --

  @spec set_project_id(String.t() | nil) :: :ok
  def set_project_id(nil) do
    Process.delete(:test_agent_project_id)
    :ok
  end

  def set_project_id(id) when is_binary(id) do
    Process.put(:test_agent_project_id, id)
    :ok
  end

  @spec project_id!() :: String.t()
  def project_id! do
    id =
      case AgentRunScope.resolve_for_current_process() do
        {:ok, %{project_id: id}} when is_binary(id) -> id
        _ -> Process.get(:test_agent_project_id)
      end

    case id do
      nil ->
        raise "test_agent_project_id not bound — scope not available via AgentRunScope or process dictionary"

      id when is_binary(id) ->
        unless Regex.match?(@uuid_re, id) do
          raise "test_agent_project_id is not a valid UUID: #{inspect(id)}"
        end

        id
    end
  end

  @spec set_commit_hash(String.t()) :: :ok
  def set_commit_hash(hash) do
    Process.put(:test_agent_commit_hash, hash)
    :ok
  end

  def commit_hash do
    case AgentRunScope.resolve_for_current_process() do
      {:ok, %{commit_hash: hash}} when is_binary(hash) -> hash
      _ -> Process.get(:test_agent_commit_hash, "")
    end
  end

  # -- Project scope guard --

  @doc """
  Validates that the payload project_id matches the bound scope.
  Returns `{:ok, scoped_project_id}` or `{:error, mismatch_result}`.
  """
  @spec validate_project_scope(String.t()) :: {:ok, String.t()} | {:error, map()}
  def validate_project_scope(payload_project_id) do
    scoped = project_id!()

    if scoped == payload_project_id do
      {:ok, scoped}
    else
      require OpenTelemetry.Tracer, as: Tracer

      Tracer.set_attribute("spotter.project_id", scoped)
      Tracer.set_attribute("spotter.payload_project_id", payload_project_id)
      Tracer.set_status(:error, "project_scope_mismatch")

      {:error,
       %{
         error: "project_scope_mismatch",
         scoped_project_id: scoped,
         payload_project_id: payload_project_id
       }}
    end
  end

  # -- Deterministic key --

  @doc "Builds a deterministic test_key from components."
  @spec build_test_key(String.t(), String.t(), [String.t()], String.t()) :: String.t()
  def build_test_key(framework, relative_path, describe_path, test_name) do
    parts = [
      String.trim(framework),
      String.trim(relative_path),
      Enum.map_join(describe_path, "::", &String.trim/1),
      String.trim(test_name)
    ]

    Enum.join(parts, "|")
  end

  # -- SQL helpers --

  def dolt_query!(sql, params \\ []) do
    SQL.query!(Repo, sql, params)
  end

  def dolt_query(sql, params \\ []) do
    SQL.query(Repo, sql, params)
  end

  def rows_to_maps(%{columns: columns, rows: rows}) do
    Enum.map(rows, fn row ->
      columns |> Enum.zip(row) |> Map.new()
    end)
  end

  # -- Readiness check --

  @doc "Returns :ok if the Dolt TestSpec.Repo is available, {:error, reason} otherwise."
  @spec check_repo_available() :: :ok | {:error, :repo_unavailable | :health_check_failed}
  def check_repo_available do
    if Process.whereis(Repo) == nil do
      {:error, :repo_unavailable}
    else
      case dolt_query("SELECT 1") do
        {:ok, _} -> :ok
        {:error, _} -> {:error, :health_check_failed}
      end
    end
  rescue
    _ -> {:error, :health_check_failed}
  end

  @doc "Detect if an error is a pool/connection timeout."
  @spec pool_timeout_error?(term()) :: boolean()
  def pool_timeout_error?(%DBConnection.ConnectionError{message: msg}),
    do: pool_timeout_message?(msg)

  def pool_timeout_error?(%MyXQL.Error{message: msg}), do: pool_timeout_message?(msg)

  def pool_timeout_error?(error) when is_binary(error), do: pool_timeout_message?(error)

  def pool_timeout_error?(error) when is_exception(error),
    do: error |> Exception.message() |> pool_timeout_message?()

  def pool_timeout_error?(_), do: false

  defp pool_timeout_message?(msg) when is_binary(msg) do
    String.contains?(msg, "connection not available") or
      String.contains?(msg, "dropped from queue") or
      String.contains?(msg, "timed out") or
      String.contains?(msg, "queue timeout")
  end

  defp pool_timeout_message?(_), do: false

  # -- Result helpers --

  def text_result(data) do
    {:ok, %{"content" => [%{"type" => "text", "text" => Jason.encode!(data)}]}}
  end
end
