defmodule Spotter.TestSpec.DoltVersioning do
  @moduledoc """
  Helpers for Dolt versioning procedures (DOLT_ADD, DOLT_COMMIT).

  Creates exactly one Dolt commit encapsulating all test spec changes for a given sync.
  """

  require OpenTelemetry.Tracer, as: Tracer

  alias Ecto.Adapters.SQL
  alias Spotter.Observability.ErrorReport
  alias Spotter.TestSpec.Repo

  @doc """
  Stages all changes and creates a Dolt commit.

  Returns `{:ok, dolt_hash}` when a commit was created, `{:ok, nil}` when
  there were no changes to commit (--skip-empty), or `{:error, reason}`.
  """
  @spec commit_if_dirty(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def commit_if_dirty(message) do
    Tracer.with_span "spotter.test_spec.dolt.commit_if_dirty" do
      Tracer.set_attribute("spotter.commit_message", message)

      result =
        with :ok <- dolt_add() do
          dolt_commit(message)
        end

      case result do
        {:ok, hash} when is_binary(hash) ->
          Tracer.set_attribute("spotter.dolt_changed", true)
          Tracer.set_attribute("spotter.dolt_commit_hash", hash)

        {:ok, nil} ->
          Tracer.set_attribute("spotter.dolt_changed", false)

        {:error, reason} ->
          ErrorReport.set_trace_error(
            "dolt_commit_error",
            inspect(reason),
            "test_spec.dolt_versioning"
          )
      end

      result
    end
  rescue
    e ->
      reason = Exception.message(e)
      ErrorReport.set_trace_error("unexpected_error", reason, "test_spec.dolt_versioning")
      {:error, reason}
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
