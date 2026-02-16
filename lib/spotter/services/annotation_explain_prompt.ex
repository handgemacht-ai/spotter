defmodule Spotter.Services.AnnotationExplainPrompt do
  @moduledoc false

  alias Spotter.Services.{FileDetail, TranscriptRenderer}
  alias Spotter.Transcripts.Message

  require Ash.Query

  @max_context_chars 20_000
  @context_window 5

  @doc """
  Builds system and user prompts for the explain annotation pipeline.
  """
  def build(annotation) do
    user_question = non_empty(annotation.comment)
    transcript_context = build_transcript_context(annotation)
    file_context = build_file_context(annotation)

    user =
      [
        "## Selected Text\n```\n#{annotation.selected_text}\n```",
        if(user_question, do: "## Question\n#{user_question}"),
        if(transcript_context != "", do: "## Surrounding Transcript\n#{transcript_context}"),
        if(file_context != "", do: "## File Context\n#{file_context}")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n\n")

    system = """
    You are an expert code explainer. Your job is to provide a clear, grounded explanation of the code or text the user has selected.

    Rules:
    - Use WebSearch and WebFetch as needed to find accurate information.
    - Provide a clear explanation in plain English.
    - Always end with a References: section listing URLs you used.
    - Do NOT fabricate sources. Only list URLs you actually visited.
    - Format: plain text/markdown for the answer body, then one URL per line prefixed with "- " in the References section.
    """

    %{system: system, user: user}
  end

  defp build_transcript_context(annotation) do
    case extract_ref_messages(annotation.message_refs) do
      [] -> ""
      messages -> build_windowed_context(annotation.session_id, messages)
    end
  end

  defp extract_ref_messages(refs) when is_list(refs) and refs != [] do
    refs |> Enum.map(& &1.message) |> Enum.reject(&is_nil/1)
  end

  defp extract_ref_messages(_), do: []

  defp build_windowed_context(session_id, messages) do
    timestamps = messages |> Enum.map(& &1.timestamp) |> Enum.reject(&is_nil/1)

    if timestamps == [] do
      format_messages(messages)
    else
      before_msgs = load_context_messages(session_id, :before, Enum.min(timestamps, DateTime))
      after_msgs = load_context_messages(session_id, :after, Enum.max(timestamps, DateTime))

      (before_msgs ++ messages ++ after_msgs)
      |> Enum.uniq_by(& &1.id)
      |> format_messages()
    end
  end

  defp load_context_messages(session_id, :before, timestamp) do
    Message
    |> Ash.Query.filter(session_id == ^session_id and timestamp < ^timestamp)
    |> Ash.Query.sort(timestamp: :desc)
    |> Ash.Query.limit(@context_window)
    |> Ash.read!()
    |> Enum.reverse()
  rescue
    _ -> []
  end

  defp load_context_messages(session_id, :after, timestamp) do
    Message
    |> Ash.Query.filter(session_id == ^session_id and timestamp > ^timestamp)
    |> Ash.Query.sort(timestamp: :asc)
    |> Ash.Query.limit(@context_window)
    |> Ash.read!()
  rescue
    _ -> []
  end

  defp format_messages(messages) do
    messages
    |> Enum.map_join("\n", fn msg ->
      text = TranscriptRenderer.extract_text(msg.content)
      "[#{msg.role}] #{text}"
    end)
    |> String.slice(0, @max_context_chars)
  end

  defp build_file_context(annotation) do
    refs = annotation.file_refs

    if is_list(refs) and refs != [] do
      Enum.map_join(refs, "\n", &format_file_ref(annotation, &1))
    else
      ""
    end
  end

  defp format_file_ref(annotation, ref) do
    header = "#{ref.relative_path}:#{ref.line_start}-#{ref.line_end}"

    case try_read_file(annotation, ref) do
      nil -> header
      content -> "#{header}\n```\n#{content}\n```"
    end
  end

  defp try_read_file(annotation, ref) do
    with path when is_binary(path) <- ref.relative_path,
         {:ok, root} <- resolve_root(annotation) do
      read_file_slice(Path.join(root, path), ref)
    else
      _ -> nil
    end
  end

  defp resolve_root(%{session: %{cwd: cwd}} = _annotation) when is_binary(cwd), do: {:ok, cwd}

  defp resolve_root(%{project_id: project_id}) when not is_nil(project_id) do
    FileDetail.resolve_repo_root(project_id)
  end

  defp resolve_root(_), do: :error

  defp read_file_slice(path, ref) do
    case File.read(path) do
      {:ok, content} ->
        lines = String.split(content, "\n")
        start = max((ref.line_start || 1) - 1, 0)
        count = (ref.line_end || ref.line_start || 1) - start

        lines
        |> Enum.slice(start, max(count, 1))
        |> Enum.join("\n")
        |> String.slice(0, 2000)

      _ ->
        nil
    end
  end

  defp non_empty(nil), do: nil
  defp non_empty(s) when is_binary(s), do: if(String.trim(s) == "", do: nil, else: s)
end
