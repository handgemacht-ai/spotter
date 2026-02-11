defmodule Spotter.Services.ReviewContextBuilder do
  @moduledoc false

  alias Spotter.Transcripts.{Annotation, Project, Session}
  require Ash.Query

  @max_text_length 300

  @doc """
  Builds compact review context for a project.
  Returns a string suitable for injection as Claude session context.
  """
  def build(project_id) do
    with {:ok, project} <- Ash.get(Project, project_id) do
      sessions = load_sessions(project.id)
      session_ids = Enum.map(sessions, & &1.id)
      sessions_by_id = Map.new(sessions, &{&1.id, &1})

      annotations = load_open_annotations(session_ids)

      {:ok, format_context(project, annotations, sessions_by_id)}
    end
  end

  defp load_sessions(project_id) do
    Session
    |> Ash.Query.filter(project_id == ^project_id)
    |> Ash.Query.sort(started_at: :desc)
    |> Ash.read!()
  end

  defp load_open_annotations([]), do: []

  defp load_open_annotations(session_ids) do
    Annotation
    |> Ash.Query.filter(session_id in ^session_ids and state == :open)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.read!()
    |> Ash.load!(message_refs: :message)
  end

  defp format_context(project, annotations, sessions_by_id) do
    header =
      "# Project Review: #{project.name}\nGenerated: #{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M UTC")}\n"

    body =
      if annotations == [] do
        "\nNo open annotations.\n"
      else
        "\n#{length(annotations)} open annotations:\n\n" <>
          Enum.map_join(annotations, "\n", &format_annotation(&1, sessions_by_id))
      end

    prompt = """

    ---
    You are reviewing code annotations for project "#{project.name}".
    For each annotation above, consider what improvements could be made.
    Propose concrete fixes, memory updates, or tooling changes grounded in the listed annotations.
    """

    header <> body <> prompt
  end

  defp format_annotation(ann, sessions_by_id) do
    session = Map.get(sessions_by_id, ann.session_id)

    session_label =
      if session, do: session.slug || String.slice(session.session_id, 0, 8), else: "unknown"

    text = truncate(ann.selected_text, @max_text_length)

    message_ids =
      case ann.message_refs do
        refs when is_list(refs) and refs != [] ->
          ids = Enum.map_join(refs, ", ", fn ref -> ref.message.uuid end)
          "  Messages: #{ids}\n"

        _ ->
          ""
      end

    """
    - [#{ann.source}] Session: #{session_label}
      Text: #{text}
      Comment: #{ann.comment}
    #{message_ids}\
    """
  end

  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "..."
end
