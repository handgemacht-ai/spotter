defmodule Spotter.Search.Indexer do
  @moduledoc """
  Populates and maintains `search_documents` for a project.

  Idempotent: upserts all documents with a shared `batch_ts`, then
  sweeps rows whose `updated_at` predates the batch (stale deletion).
  """

  require Logger
  require OpenTelemetry.Tracer
  require Ash.Query

  alias Spotter.Repo
  alias Spotter.Services.FileDetail
  alias Spotter.Transcripts.{Annotation, CommitHotspot, Session}

  @chunk_size 300

  @spec reindex_project(String.t(), keyword()) :: :ok
  def reindex_project(project_id, _opts \\ []) do
    OpenTelemetry.Tracer.with_span "spotter.search.reindex_project" do
      OpenTelemetry.Tracer.set_attribute("spotter.project_id", project_id)
      batch_ts = DateTime.utc_now()

      docs =
        List.flatten([
          build_session_docs(project_id),
          build_commit_docs(project_id),
          build_hotspot_docs(project_id),
          build_annotation_docs(project_id),
          build_file_docs(project_id)
        ])

      OpenTelemetry.Tracer.set_attribute("spotter.search.docs_indexed_total", length(docs))

      upsert_and_sweep(project_id, docs, batch_ts)
      :ok
    end
  end

  # --- Document builders ---

  defp build_session_docs(project_id) do
    Session
    |> Ash.Query.filter(project_id == ^project_id)
    |> Ash.read!()
    |> Enum.map(fn s ->
      title = s.custom_title || s.slug || short_id(s.session_id)

      subtitle =
        [s.git_branch || "?", format_datetime(s.started_at)]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" \u00B7 ")

      search_parts =
        [
          to_string(s.session_id),
          s.slug,
          s.git_branch,
          s.cwd,
          s.summary,
          s.first_prompt,
          s.distilled_summary
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")

      %{
        kind: "session",
        project_id: project_id,
        external_id: to_string(s.session_id),
        title: title,
        subtitle: subtitle,
        url: "/sessions/#{s.session_id}",
        search_text: search_parts
      }
    end)
  end

  defp build_commit_docs(project_id) do
    sql = """
    SELECT DISTINCT c.id, c.commit_hash, c.subject, c.body,
           c.author_name, c.author_email, c.committed_at, c.changed_files
    FROM commits c
    JOIN session_commit_links scl ON scl.commit_id = c.id
    JOIN sessions s ON s.id = scl.session_id
    WHERE s.project_id = ?
    """

    case Repo.query(sql, [project_id]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, &commit_row_to_doc(&1, project_id))

      {:error, reason} ->
        Logger.warning("Search indexer: commit query failed: #{inspect(reason)}")
        []
    end
  end

  defp commit_row_to_doc(
         [id, commit_hash, subject, body, author_name, author_email, committed_at, changed_files],
         project_id
       ) do
    short_hash = String.slice(commit_hash || "", 0, 7)
    subject = if subject && subject != "", do: subject, else: "(no subject)"

    subtitle =
      [author_name, committed_at]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" \u00B7 ")

    files_str = if is_binary(changed_files), do: changed_files, else: ""

    search_parts =
      [commit_hash, subject, body, author_name, author_email, files_str]
      |> Enum.reject(&(&1 == "" || is_nil(&1)))
      |> Enum.join(" ")

    %{
      kind: "commit",
      project_id: project_id,
      external_id: id,
      title: "#{short_hash} #{subject}",
      subtitle: subtitle,
      url: "/history/commits/#{id}",
      search_text: search_parts
    }
  end

  defp build_hotspot_docs(project_id) do
    CommitHotspot
    |> Ash.Query.filter(project_id == ^project_id)
    |> Ash.read!()
    |> Enum.map(fn h ->
      title = "#{h.relative_path}:#{h.line_start}-#{h.line_end}"
      score_str = Float.round(h.overall_score || 0.0, 1) |> to_string()

      search_parts =
        [h.relative_path, h.symbol_name, h.reason, h.snippet]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")

      %{
        kind: "commit_hotspot",
        project_id: project_id,
        external_id: h.id,
        title: title,
        subtitle: "Hotspot \u00B7 score #{score_str}",
        url:
          "/projects/#{project_id}/files/#{h.relative_path}?line_start=#{h.line_start}&line_end=#{h.line_end}&hotspot_id=#{h.id}",
        search_text: search_parts
      }
    end)
  end

  defp build_annotation_docs(project_id) do
    Annotation
    |> Ash.Query.filter(project_id == ^project_id)
    |> Ash.Query.load(:session)
    |> Ash.read!()
    |> Enum.map(fn a ->
      text_preview = String.slice(a.comment || a.selected_text || "", 0, 80)

      url = annotation_url(a, project_id)

      search_parts =
        [
          a.comment,
          a.selected_text,
          a.relative_path,
          a.session && to_string(a.session.session_id)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")

      %{
        kind: "annotation",
        project_id: project_id,
        external_id: a.id,
        title: "Annotation: #{text_preview}",
        subtitle: "#{a.state} \u00B7 #{a.purpose}",
        url: url,
        search_text: search_parts
      }
    end)
  end

  defp build_file_docs(project_id) do
    with {:ok, repo_root} <- FileDetail.resolve_repo_root(project_id),
         {output, 0} <-
           System.cmd("git", ["-C", repo_root, "ls-files", "-z"], stderr_to_stdout: true) do
      files = String.split(output, <<0>>, trim: true)
      files_to_docs(files, project_id)
    else
      {:error, _} ->
        Logger.info(
          "Search indexer: no repo root for project #{project_id}, skipping file indexing"
        )

        []

      _ ->
        Logger.warning("Search indexer: git ls-files failed for project #{project_id}")
        []
    end
  rescue
    e ->
      Logger.warning("Search indexer: file indexing failed: #{inspect(e)}")
      []
  end

  defp files_to_docs(files, project_id) do
    file_docs =
      Enum.map(files, fn path ->
        %{
          kind: "file",
          project_id: project_id,
          external_id: path,
          title: path,
          subtitle: "File",
          url: "/projects/#{project_id}/files/#{path}",
          search_text: path <> " " <> spacify_path(path)
        }
      end)

    dir_docs =
      files
      |> Enum.flat_map(&parent_dirs/1)
      |> Enum.uniq()
      |> Enum.map(fn dir ->
        %{
          kind: "directory",
          project_id: project_id,
          external_id: dir,
          title: dir <> "/",
          subtitle: "Directory",
          url: "/projects/#{project_id}/files/#{dir}",
          search_text: dir <> " " <> spacify_path(dir)
        }
      end)

    file_docs ++ dir_docs
  end

  # --- Upsert + sweep ---

  defp upsert_and_sweep(project_id, docs, batch_ts) do
    docs
    |> Enum.chunk_every(@chunk_size)
    |> Enum.each(&upsert_chunk(&1, batch_ts))

    sweep_stale(project_id, batch_ts)
  end

  defp upsert_chunk(docs, batch_ts) do
    Enum.each(docs, fn doc ->
      Repo.query!(
        """
        INSERT INTO search_documents (id, project_id, kind, external_id, title, subtitle, url, search_text, inserted_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (project_id, kind, external_id)
        DO UPDATE SET title = excluded.title, subtitle = excluded.subtitle,
                      url = excluded.url, search_text = excluded.search_text,
                      updated_at = excluded.updated_at
        """,
        [
          Ecto.UUID.generate(),
          doc.project_id,
          doc.kind,
          doc.external_id,
          doc.title,
          doc.subtitle,
          doc.url,
          doc.search_text,
          batch_ts,
          batch_ts
        ]
      )
    end)
  end

  defp sweep_stale(project_id, batch_ts) do
    Repo.query!(
      "DELETE FROM search_documents WHERE project_id = ? AND updated_at < ?",
      [project_id, batch_ts]
    )
  end

  # --- Helpers ---

  defp annotation_url(a, project_id) do
    if a.relative_path do
      base = "/projects/#{project_id}/files/#{a.relative_path}?annotation_id=#{a.id}"

      base <>
        if(a.line_start, do: "&line_start=#{a.line_start}", else: "") <>
        if(a.line_end, do: "&line_end=#{a.line_end}", else: "")
    else
      session_id = if a.session, do: a.session.session_id, else: "unknown"
      "/sessions/#{session_id}"
    end
  end

  defp short_id(nil), do: "?"
  defp short_id(id), do: String.slice(to_string(id), 0, 8)

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp spacify_path(path) do
    String.replace(path, ~r"[/._\-]", " ")
  end

  defp parent_dirs(path) do
    path
    |> Path.split()
    |> Enum.drop(-1)
    |> Enum.scan(fn segment, acc -> acc <> "/" <> segment end)
  end
end
