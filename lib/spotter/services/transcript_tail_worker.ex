defmodule Spotter.Services.TranscriptTailWorker do
  @moduledoc false
  use GenServer

  alias Spotter.Transcripts.Jobs.SyncTranscripts

  require Logger

  @debounce_ms 500
  @default_adapter Spotter.Services.TranscriptTailAdapter.TailF

  defstruct [
    :session_id,
    :transcript_path,
    :adapter_mod,
    :adapter_state,
    :debounce_ref,
    lines_buffered: 0
  ]

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  def via(session_id) do
    {:via, Registry, {Spotter.Services.TranscriptTailRegistry, session_id}}
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    transcript_path = Keyword.fetch!(opts, :transcript_path)
    adapter_mod = Keyword.get(opts, :adapter, @default_adapter)

    state = %__MODULE__{
      session_id: session_id,
      transcript_path: transcript_path,
      adapter_mod: adapter_mod
    }

    case adapter_mod.start(session_id, transcript_path, self()) do
      {:ok, adapter_state} ->
        {:ok, %{state | adapter_state: adapter_state}}

      {:error, reason} ->
        Logger.warning(
          "TailWorker: failed to start adapter for #{session_id}: #{inspect(reason)}"
        )

        {:stop, {:adapter_start_failed, reason}}
    end
  end

  @impl true
  def handle_info({_port, {:data, _data}}, state) do
    state = %{state | lines_buffered: state.lines_buffered + 1}
    state = schedule_debounce(state)
    {:noreply, state}
  end

  def handle_info({_port, {:exit_status, code}}, state) do
    Logger.info("TailWorker: tail process exited for #{state.session_id} with code #{code}")

    {:stop, {:tail_exited, code}, %{state | adapter_state: nil}}
  end

  def handle_info(:flush, state) do
    if state.lines_buffered > 0 do
      flush_and_broadcast(state)
    end

    {:noreply, %{state | lines_buffered: 0, debounce_ref: nil}}
  end

  @impl true
  def handle_call(:stop_with_flush, _from, state) do
    state = cancel_debounce(state)
    best_effort_flush(state)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    best_effort_flush(state)

    if state.adapter_state do
      state.adapter_mod.stop(state.adapter_state)
    end
  end

  defp schedule_debounce(%{debounce_ref: nil} = state) do
    ref = Process.send_after(self(), :flush, @debounce_ms)
    %{state | debounce_ref: ref}
  end

  defp schedule_debounce(state), do: state

  defp cancel_debounce(%{debounce_ref: nil} = state), do: state

  defp cancel_debounce(%{debounce_ref: ref} = state) do
    Process.cancel_timer(ref)
    %{state | debounce_ref: nil}
  end

  defp best_effort_flush(state) do
    if state.lines_buffered > 0 do
      flush_and_broadcast(state)
    end
  rescue
    e ->
      Logger.warning(
        "TailWorker: flush on stop failed for #{state.session_id}: #{Exception.message(e)}"
      )
  end

  defp flush_and_broadcast(state) do
    result = SyncTranscripts.sync_session_file(state.transcript_path)

    if result.status == :ok and result.ingested_messages > 0 do
      Phoenix.PubSub.broadcast(
        Spotter.PubSub,
        "session_transcripts:#{state.session_id}",
        {:transcript_updated, state.session_id, result.ingested_messages}
      )
    end
  end
end
