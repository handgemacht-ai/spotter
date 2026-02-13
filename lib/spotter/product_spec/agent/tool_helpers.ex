defmodule Spotter.ProductSpec.Agent.ToolHelpers do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias Spotter.ProductSpec.Repo

  @spec_key_re ~r/^[a-z0-9][a-z0-9-]{2,159}$/

  @doc "Sets the git commit hash used by write tools for `updated_by_git_commit`."
  @spec set_commit_hash(String.t()) :: :ok
  def set_commit_hash(hash) do
    Process.put(:spec_agent_commit_hash, hash)
    :ok
  end

  def commit_hash, do: Process.get(:spec_agent_commit_hash, "")

  @doc "Sets the git working directory for repo inspection tools."
  @spec set_git_cwd(String.t() | nil) :: :ok
  def set_git_cwd(cwd) do
    Process.put(:spec_agent_git_cwd, cwd)
    :ok
  end

  def git_cwd, do: Process.get(:spec_agent_git_cwd)

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
end
