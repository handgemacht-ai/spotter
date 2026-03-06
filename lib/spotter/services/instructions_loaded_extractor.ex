defmodule Spotter.Services.InstructionsLoadedExtractor do
  @moduledoc """
  Extracts InstructionsLoaded events from raw hook events and persists
  them as derived InstructionsLoadedEvent records.

  Follows the same fail-open pattern as ShellCommandExtractor.
  """

  alias Spotter.Transcripts.{InstructionsLoadedEvent, Session}

  require Ash.Query
  require Logger

  @spec extract_and_persist(map(), String.t()) ::
          {:ok, String.t() | nil} | {:error, term()}
  def extract_and_persist(hook_payload, raw_hook_event_id) do
    if hook_payload["hook_event_name"] != "InstructionsLoaded" do
      {:ok, nil}
    else
      do_extract(hook_payload, raw_hook_event_id)
    end
  rescue
    error ->
      Logger.warning("InstructionsLoadedExtractor failed: #{Exception.message(error)}")
      {:ok, nil}
  end

  defp do_extract(hook_payload, raw_hook_event_id) do
    file_path = hook_payload["file_path"]

    if not is_binary(file_path) or file_path == "" do
      {:ok, nil}
    else
      persist_event(hook_payload, raw_hook_event_id, file_path)
    end
  end

  defp persist_event(hook_payload, raw_hook_event_id, file_path) do
    metrics = hook_payload["spotter_instruction_metrics"] || %{}
    session_id = hook_payload["session_id"]
    {internal_session_id, project_id} = resolve_session_and_project(session_id)

    attrs = %{
      raw_hook_event_id: raw_hook_event_id,
      external_session_id: session_id,
      session_id: internal_session_id,
      project_id: project_id,
      file_path: file_path,
      memory_type: safe_string(hook_payload["memory_type"]),
      load_reason: safe_string(hook_payload["load_reason"]),
      bytes_loaded: safe_integer(metrics["bytes_loaded"], 0),
      lines_loaded: safe_integer(metrics["lines_loaded"], 0),
      size_status: safe_string(metrics["size_status"]) || "unknown",
      captured_at: parse_captured_at(hook_payload["captured_at"])
    }

    case Ash.create(InstructionsLoadedEvent, attrs, action: :upsert) do
      {:ok, _event} ->
        maybe_broadcast(project_id)
        {:ok, project_id}

      {:error, reason} ->
        Logger.debug("InstructionsLoadedEvent upsert failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_broadcast(nil), do: :ok
  defp maybe_broadcast(project_id), do: broadcast_instructions_telemetry(project_id)

  defp resolve_session_and_project(session_id) when is_binary(session_id) and session_id != "" do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %Session{} = session} -> {session.id, session.project_id}
      _ -> {nil, nil}
    end
  end

  defp resolve_session_and_project(_), do: {nil, nil}

  defp broadcast_instructions_telemetry(project_id) do
    Phoenix.PubSub.broadcast(
      Spotter.PubSub,
      "instructions_telemetry:project:#{project_id}",
      {:instructions_telemetry_updated, %{project_id: project_id}}
    )
  rescue
    _ -> :ok
  end

  defp safe_string(val) when is_binary(val) and val != "", do: val
  defp safe_string(_), do: nil

  defp safe_integer(val, _default) when is_integer(val), do: val

  defp safe_integer(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  defp safe_integer(_, default), do: default

  defp parse_captured_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp parse_captured_at(_), do: DateTime.utc_now()
end
