defmodule Spotter.Services.TranscriptTailSupervisor do
  @moduledoc false
  use DynamicSupervisor

  alias Spotter.Services.TranscriptTailWorker

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Ensures a single tail worker is running for the given session.
  Idempotent — returns :ok if worker already exists.
  """
  def ensure_worker(session_id, transcript_path) do
    case Registry.lookup(Spotter.Services.TranscriptTailRegistry, session_id) do
      [{_pid, _}] ->
        :ok

      [] ->
        spec = {
          TranscriptTailWorker,
          session_id: session_id, transcript_path: transcript_path
        }

        case DynamicSupervisor.start_child(__MODULE__, spec) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc """
  Stops the tail worker for a session if one is running.
  """
  def stop_worker(session_id) do
    case Registry.lookup(Spotter.Services.TranscriptTailRegistry, session_id) do
      [{pid, _}] ->
        try do
          GenServer.call(pid, :stop_with_flush, 5_000)
        catch
          :exit, _ -> :ok
        end

      [] ->
        :ok
    end
  end
end
