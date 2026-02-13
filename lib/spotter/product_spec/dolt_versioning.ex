defmodule Spotter.ProductSpec.DoltVersioning do
  @moduledoc """
  Helpers for Dolt versioning procedures (DOLT_ADD, DOLT_COMMIT).

  Creates exactly one Dolt commit encapsulating all spec changes for a given Git commit.
  """

  alias Ecto.Adapters.SQL
  alias Spotter.ProductSpec.Repo

  @doc """
  Stages all changes and creates a Dolt commit.

  Returns `{:ok, dolt_hash}` when a commit was created, `{:ok, nil}` when
  there were no changes to commit (--skip-empty), or `{:error, reason}`.
  """
  @spec commit_spec_changes(String.t(), String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def commit_spec_changes(commit_hash, commit_subject) do
    message = "spotter: rolling-spec #{commit_hash} #{commit_subject}"

    with :ok <- dolt_add() do
      dolt_commit(message)
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp dolt_add do
    SQL.query!(Repo, "CALL DOLT_ADD('-A')")
    :ok
  end

  defp dolt_commit(message) do
    case SQL.query(Repo, "CALL DOLT_COMMIT('--skip-empty', '-m', ?)", [message]) do
      {:ok, %{rows: [[hash]]}} when is_binary(hash) and hash != "" ->
        {:ok, hash}

      {:ok, _} ->
        {:ok, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
