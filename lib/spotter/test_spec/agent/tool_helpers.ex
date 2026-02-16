defmodule Spotter.TestSpec.Agent.ToolHelpers do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias Spotter.TestSpec.Repo

  @uuid_re ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  # -- Process-dictionary scope binding --

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
    case Process.get(:test_agent_project_id) do
      nil ->
        raise "test_agent_project_id not bound — call ToolHelpers.set_project_id/1 first"

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

  def commit_hash, do: Process.get(:test_agent_commit_hash, "")

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

  # -- Result helpers --

  def text_result(data) do
    {:ok, %{"content" => [%{"type" => "text", "text" => Jason.encode!(data)}]}}
  end
end
