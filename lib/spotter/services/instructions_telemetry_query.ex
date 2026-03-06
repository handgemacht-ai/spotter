defmodule Spotter.Services.InstructionsTelemetryQuery do
  @moduledoc false

  alias Spotter.Transcripts.InstructionsLoadedEvent

  require Ash.Query

  @window_seconds %{
    last_24h: 86_400,
    last_7d: 604_800,
    last_30d: 2_592_000
  }

  @spec query(String.t() | nil, keyword()) :: map()
  def query(project_id, opts \\ []) do
    window = Keyword.get(opts, :window, :last_7d)
    events = load_events(project_id, window)

    %{
      summary: build_summary(events),
      documents: build_document_rows(events),
      sessions: build_session_rows(events)
    }
  end

  defp load_events(project_id, window) do
    base = InstructionsLoadedEvent |> Ash.Query.new()

    base =
      if project_id do
        Ash.Query.filter(base, project_id == ^project_id)
      else
        base
      end

    base =
      case Map.get(@window_seconds, window) do
        nil ->
          base

        seconds ->
          cutoff = DateTime.add(DateTime.utc_now(), -seconds, :second)
          Ash.Query.filter(base, captured_at >= ^cutoff)
      end

    Ash.read!(base)
  end

  defp build_summary(events) do
    %{
      total_loads: length(events),
      unique_documents: events |> Enum.map(& &1.file_path) |> Enum.uniq() |> length(),
      unique_sessions:
        events
        |> Enum.map(& &1.external_session_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> length(),
      total_bytes: events |> Enum.map(& &1.bytes_loaded) |> Enum.sum(),
      total_lines: events |> Enum.map(& &1.lines_loaded) |> Enum.sum()
    }
  end

  defp build_document_rows(events) do
    events
    |> Enum.group_by(& &1.file_path)
    |> Enum.map(fn {file_path, group} ->
      %{
        file_path: file_path,
        load_count: length(group),
        session_count:
          group
          |> Enum.map(& &1.external_session_id)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> length(),
        total_bytes: group |> Enum.map(& &1.bytes_loaded) |> Enum.sum(),
        total_lines: group |> Enum.map(& &1.lines_loaded) |> Enum.sum(),
        last_seen_at: group |> Enum.map(& &1.captured_at) |> Enum.max(DateTime)
      }
    end)
    |> Enum.sort_by(& &1.load_count, :desc)
  end

  defp build_session_rows(events) do
    events
    |> Enum.reject(&is_nil(&1.external_session_id))
    |> Enum.group_by(& &1.external_session_id)
    |> Enum.map(fn {session_id, group} ->
      %{
        external_session_id: session_id,
        load_count: length(group),
        document_count: group |> Enum.map(& &1.file_path) |> Enum.uniq() |> length(),
        total_bytes: group |> Enum.map(& &1.bytes_loaded) |> Enum.sum(),
        total_lines: group |> Enum.map(& &1.lines_loaded) |> Enum.sum(),
        last_seen_at: group |> Enum.map(& &1.captured_at) |> Enum.max(DateTime)
      }
    end)
    |> Enum.sort_by(& &1.load_count, :desc)
  end
end
