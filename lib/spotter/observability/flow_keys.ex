defmodule Spotter.Observability.FlowKeys do
  @moduledoc """
  Helpers for constructing and parsing flow key strings.

  Flow keys are namespaced identifiers like `session:abc123` or `commit:deadbeef`
  that connect events into logical flows for the DAG visualization.
  """

  @doc "Build a session flow key."
  @spec session(String.t()) :: String.t()
  def session(id) when is_binary(id), do: "session:#{id}"

  @doc "Build a commit flow key."
  @spec commit(String.t()) :: String.t()
  def commit(hash) when is_binary(hash), do: "commit:#{hash}"

  @doc "Build a project flow key."
  @spec project(String.t() | integer()) :: String.t()
  def project(id), do: "project:#{id}"

  @doc "Build an Oban job flow key."
  @spec oban(String.t() | integer()) :: String.t()
  def oban(job_id), do: "oban:#{job_id}"

  @doc "Build an agent run flow key."
  @spec agent_run(String.t()) :: String.t()
  def agent_run(run_id) when is_binary(run_id), do: "agent_run:#{run_id}"

  @doc "The system-level flow key."
  @spec system() :: String.t()
  def system, do: "system"

  @doc """
  Derive flow keys from a map of args (e.g. Oban job args or hook params).

  Extracts known fields and builds the corresponding flow keys.
  """
  @spec derive(map()) :: [String.t()]
  def derive(args) when is_map(args) do
    []
    |> maybe_add(args, "session_id", &session/1)
    |> maybe_add(args, "commit_hash", &commit/1)
    |> maybe_add(args, "project_id", &project/1)
    |> maybe_add(args, "job_id", &oban/1)
    |> maybe_add(args, "run_id", &agent_run/1)
    |> maybe_add_atom_keys(args)
    |> Enum.uniq()
  end

  def derive(_), do: []

  defp maybe_add(keys, args, key, builder) do
    case Map.get(args, key) do
      nil -> keys
      "" -> keys
      val -> [builder.(to_string(val)) | keys]
    end
  end

  defp maybe_add_atom_keys(keys, args) do
    keys
    |> maybe_add(args, :session_id, &session/1)
    |> maybe_add(args, :commit_hash, &commit/1)
    |> maybe_add(args, :project_id, &project/1)
    |> maybe_add(args, :job_id, &oban/1)
    |> maybe_add(args, :run_id, &agent_run/1)
  end
end
