defmodule Spotter.Services.SubagentLifecycleIngestor do
  @moduledoc """
  Ingests SubagentStart/SubagentStop raw hook events into the subagents table.

  Deterministic lifecycle enrichment: maps hook metadata (agent_id, agent_type)
  into subagent rows with fail-safe, non-blocking semantics.
  """

  alias Spotter.Transcripts.{Session, Sessions, Subagent}

  require Ash.Query
  require Logger

  @lifecycle_events ~w(SubagentStart SubagentStop)

  @spec ingest(map(), Spotter.Transcripts.RawHookEvent.t()) ::
          {:ok, %{status: atom(), session_id: String.t() | nil, agent_id: String.t() | nil}}
          | {:error, term()}
  def ingest(hook_payload, raw_hook_event) do
    hook_event_name = hook_payload["hook_event_name"]
    agent_id = hook_payload["agent_id"]
    session_id = hook_payload["session_id"]

    cond do
      hook_event_name not in @lifecycle_events ->
        {:ok, %{status: :ignored, session_id: session_id, agent_id: agent_id}}

      not is_binary(agent_id) or agent_id == "" ->
        {:ok, %{status: :ignored, session_id: session_id, agent_id: nil}}

      true ->
        do_ingest(hook_payload, raw_hook_event)
    end
  rescue
    error ->
      Logger.warning("Subagent lifecycle ingest failed: #{Exception.message(error)}")

      {:error, error}
  end

  defp do_ingest(hook_payload, raw_hook_event) do
    session_id = hook_payload["session_id"]
    agent_id = hook_payload["agent_id"]
    agent_type = hook_payload["agent_type"]
    captured_at = raw_hook_event.captured_at

    with {:ok, session} <- resolve_session(session_id, hook_payload["cwd"]) do
      case hook_payload["hook_event_name"] do
        "SubagentStart" ->
          upsert_subagent_start(session, agent_id, agent_type, captured_at)

        "SubagentStop" ->
          upsert_subagent_stop(session, agent_id, agent_type, captured_at)
      end
    end
  end

  defp upsert_subagent_start(session, agent_id, agent_type, captured_at) do
    case find_existing(session.id, agent_id) do
      nil ->
        attrs = %{
          agent_id: agent_id,
          session_id: session.id,
          subagent_type: non_empty(agent_type),
          started_at: captured_at
        }

        Ash.create!(Subagent, attrs)
        {:ok, %{status: :created, session_id: session.session_id, agent_id: agent_id}}

      existing ->
        update_attrs = %{
          subagent_type: first_non_empty(non_empty(agent_type), existing.subagent_type),
          started_at: earliest_non_nil(existing.started_at, captured_at)
        }

        Ash.update!(existing, update_attrs)
        {:ok, %{status: :updated, session_id: session.session_id, agent_id: agent_id}}
    end
  end

  defp upsert_subagent_stop(session, agent_id, agent_type, captured_at) do
    case find_existing(session.id, agent_id) do
      nil ->
        attrs = %{
          agent_id: agent_id,
          session_id: session.id,
          subagent_type: non_empty(agent_type),
          ended_at: captured_at
        }

        Ash.create!(Subagent, attrs)
        {:ok, %{status: :created, session_id: session.session_id, agent_id: agent_id}}

      existing ->
        update_attrs = %{
          subagent_type: first_non_empty(non_empty(agent_type), existing.subagent_type),
          ended_at: latest_non_nil(existing.ended_at, captured_at)
        }

        Ash.update!(existing, update_attrs)
        {:ok, %{status: :updated, session_id: session.session_id, agent_id: agent_id}}
    end
  end

  defp find_existing(session_id, agent_id) do
    Subagent
    |> Ash.Query.filter(session_id == ^session_id and agent_id == ^agent_id)
    |> Ash.read!()
    |> List.first()
  end

  defp resolve_session(session_id, cwd) when is_binary(session_id) and session_id != "" do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, nil} -> Sessions.find_or_create(session_id, cwd)
      {:ok, session} -> {:ok, session}
      {:error, _} -> Sessions.find_or_create(session_id, cwd)
    end
  end

  defp resolve_session(_, _), do: {:error, :missing_session_id}

  defp non_empty(nil), do: nil
  defp non_empty(""), do: nil
  defp non_empty(val) when is_binary(val), do: val

  defp first_non_empty(nil, existing), do: existing
  defp first_non_empty(new, _existing), do: new

  defp earliest_non_nil(nil, b), do: b
  defp earliest_non_nil(a, nil), do: a

  defp earliest_non_nil(a, b) do
    if DateTime.compare(a, b) in [:lt, :eq], do: a, else: b
  end

  defp latest_non_nil(nil, b), do: b
  defp latest_non_nil(a, nil), do: a

  defp latest_non_nil(a, b) do
    if DateTime.compare(a, b) in [:gt, :eq], do: a, else: b
  end
end
