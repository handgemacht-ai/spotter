defmodule Spotter.Transcripts.SessionPresenter do
  @moduledoc """
  Pure presentation helpers for session labels and timestamps.
  """

  @max_prompt_length 72

  @doc """
  Returns the primary display label for a session.

  Precedence: custom_title > summary > slug > first_prompt (truncated) > short session_id.
  """
  def primary_label(session) do
    non_empty(session.custom_title) ||
      non_empty(Map.get(session, :distilled_summary)) ||
      non_empty(session.summary) ||
      non_empty(session.slug) ||
      truncate_prompt(session.first_prompt) ||
      short_id(session.session_id)
  end

  @doc """
  Returns a secondary label line: "slug:<slug> · id:<short-id>".
  """
  def secondary_label(session) do
    slug_part = non_empty(session.slug) || "\u2014"
    id_part = short_id(session.session_id)
    "slug:#{slug_part} \u00b7 id:#{id_part}"
  end

  @doc """
  Returns `%{relative: String.t(), absolute: String.t()}` for a started_at timestamp,
  or nil if the input is nil.

  Accepts an optional `now` parameter for deterministic testing.
  """
  def started_display(dt, now \\ nil)
  def started_display(nil, _now), do: nil

  def started_display(dt, now) do
    now = now || DateTime.utc_now()
    %{relative: relative_time(dt, now), absolute: format_absolute(dt)}
  end

  defp relative_time(dt, now) do
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp format_absolute(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp truncate_prompt(nil), do: nil

  defp truncate_prompt(text) do
    normalized =
      text
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    case normalized do
      "" ->
        nil

      s when byte_size(s) <= @max_prompt_length ->
        s

      s ->
        String.slice(s, 0, @max_prompt_length - 1) <> "\u2026"
    end
  end

  defp short_id(nil), do: "????????"
  defp short_id(id), do: String.slice(to_string(id), 0, 8)

  defp non_empty(nil), do: nil
  defp non_empty(""), do: nil

  defp non_empty(str) when is_binary(str) do
    case String.trim(str) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
