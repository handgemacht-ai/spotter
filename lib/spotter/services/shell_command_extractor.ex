defmodule Spotter.Services.ShellCommandExtractor do
  @moduledoc false

  alias Spotter.Transcripts.{Session, ShellCommandEvent}
  alias Spotter.Transcripts.Sessions

  require Ash.Query
  require Logger

  @max_traverse_depth 20
  @max_command_length 10_240

  @phase_map %{
    "PreToolUse" => {:start, nil},
    "PostToolUse" => {:finish, :ok},
    "PostToolUseFailure" => {:finish, :error}
  }

  @doc """
  Extracts shell command events from a raw hook event and persists them.

  Returns `{:ok, count, project_id}` with the number of events created, or `{:error, reason}`.
  Never raises.
  """
  @spec extract_and_persist(map(), String.t()) ::
          {:ok, non_neg_integer(), String.t() | nil} | {:error, term()}
  def extract_and_persist(hook_payload, _raw_hook_event_id) when not is_map(hook_payload) do
    {:ok, 0, nil}
  end

  def extract_and_persist(hook_payload, raw_hook_event_id) do
    hook_event_name = hook_payload["hook_event_name"]

    case resolve_phase(hook_event_name) do
      {:ok, phase, finish_status} ->
        commands = extract_commands(hook_payload)

        if commands == [] do
          {:ok, 0, nil}
        else
          persist_commands(commands, hook_payload, raw_hook_event_id, phase, finish_status)
        end

      {:error, :not_tool_event} ->
        {:ok, 0, nil}
    end
  rescue
    error ->
      Logger.warning("ShellCommandExtractor failed: #{Exception.message(error)}")

      {:ok, 0, nil}
  end

  @doc """
  Recursively extracts all string values under keys named "command" from the payload.
  Returns a list of `{command, command_path}` tuples.
  """
  @spec extract_commands(map()) :: [{String.t(), String.t()}]
  def extract_commands(payload) when is_map(payload) do
    traverse(payload, "", 0)
  end

  def extract_commands(_), do: []

  defp traverse(_value, _path, depth) when depth > @max_traverse_depth, do: []

  defp traverse(map, path, depth) when is_map(map) do
    Enum.flat_map(map, fn {key, value} ->
      current_path = append_path(path, key)

      case {key, value} do
        {"command", command} when is_binary(command) ->
          [{truncate_command(command), current_path}]

        {_key, nested} ->
          traverse(nested, current_path, depth + 1)
      end
    end)
  end

  defp traverse(list, path, depth) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} ->
      traverse(item, append_path(path, Integer.to_string(index)), depth + 1)
    end)
  end

  defp traverse(_value, _path, _depth), do: []

  defp append_path("", key), do: key
  defp append_path(path, key), do: "#{path}.#{key}"

  defp truncate_command(command) when byte_size(command) > @max_command_length do
    String.slice(command, 0, @max_command_length) <> "[truncated]"
  end

  defp truncate_command(command), do: command

  defp persist_commands(commands, hook_payload, raw_hook_event_id, phase, finish_status) do
    session_id = hook_payload["session_id"]
    tool_use_id = hook_payload["tool_use_id"]
    tool_name = hook_payload["tool_name"]
    captured_at = parse_captured_at(hook_payload["captured_at"])

    case resolve_session(session_id) do
      {:ok, session} ->
        base_attrs = %{
          session_id: session.id,
          external_session_id: session_id,
          project_id: session.project_id,
          tool_use_id: tool_use_id || "unknown_#{Ash.UUID.generate()}",
          tool_name: tool_name,
          hook_event_name: hook_payload["hook_event_name"],
          phase: phase,
          finish_status: finish_status,
          captured_at: captured_at,
          raw_hook_event_id: raw_hook_event_id
        }

        count = Enum.count(commands, &upsert_command(&1, base_attrs))
        {:ok, count, session.project_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp upsert_command({command, command_path}, base_attrs) do
    attrs = Map.merge(base_attrs, %{command: command, command_path: command_path})

    case Ash.create(ShellCommandEvent, attrs, action: :upsert) do
      {:ok, _} ->
        true

      {:error, reason} ->
        Logger.debug("ShellCommandEvent upsert failed: #{inspect(reason)}")
        false
    end
  end

  defp resolve_phase(event_name) when is_binary(event_name) do
    case Map.fetch(@phase_map, event_name) do
      {:ok, {phase, status}} -> {:ok, phase, status}
      :error -> {:error, :not_tool_event}
    end
  end

  defp resolve_phase(_), do: {:error, :not_tool_event}

  defp resolve_session(session_id) when is_binary(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, %Session{} = session} -> {:ok, session}
      {:ok, nil} -> Sessions.find_or_create(session_id)
      {:error, _} = error -> error
    end
  end

  defp resolve_session(_), do: {:error, :missing_session_id}

  defp parse_captured_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp parse_captured_at(_), do: DateTime.utc_now()
end
