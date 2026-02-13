defmodule Spotter.Services.FileDetail do
  @moduledoc "Data service for the file detail page."

  alias Spotter.Services.CommitDetail

  alias Spotter.Transcripts.{
    Annotation,
    AnnotationFileRef,
    Commit,
    CommitFile,
    FileSnapshot,
    Session,
    SessionCommitLink
  }

  require Ash.Query

  @doc """
  Resolves a project by ID. Returns `{:ok, project}` or `{:error, :not_found}`.
  """
  def load_project(project_id) do
    case Ash.get(Spotter.Transcripts.Project, project_id) do
      {:ok, project} -> {:ok, project}
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Loads the latest file content for a relative path.

  Tries FileSnapshot.content_after first; falls back to git blob.
  """
  def load_file_content(project_id, relative_path) do
    snapshot =
      FileSnapshot
      |> Ash.Query.filter(relative_path == ^relative_path)
      |> Ash.Query.load(:session)
      |> Ash.Query.sort(timestamp: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read!()
      |> List.first()

    if snapshot && snapshot.content_after do
      {:ok, snapshot.content_after}
    else
      fetch_git_blob(project_id, relative_path)
    end
  end

  @doc """
  Loads commits that touched a file path, via CommitFile rows.
  """
  def load_commits_for_file(relative_path) do
    commit_files =
      CommitFile
      |> Ash.Query.filter(relative_path == ^relative_path)
      |> Ash.read!()

    commit_ids = Enum.map(commit_files, & &1.commit_id) |> Enum.uniq()

    if commit_ids == [] do
      []
    else
      change_types = Map.new(commit_files, &{&1.commit_id, &1.change_type})

      Commit
      |> Ash.Query.filter(id in ^commit_ids)
      |> Ash.Query.sort(committed_at: :desc, inserted_at: :desc)
      |> Ash.read!()
      |> Enum.map(fn commit ->
        %{commit: commit, change_type: Map.get(change_types, commit.id, :modified)}
      end)
    end
  end

  @doc """
  Loads sessions linked to commits that touched a file, for transcript navigation.
  """
  def load_sessions_for_file(relative_path) do
    commit_ids =
      relative_path
      |> load_commits_for_file()
      |> Enum.map(& &1.commit.id)

    links = load_session_links(commit_ids)
    sessions_by_id = load_sessions_by_id(links)

    links
    |> Enum.group_by(& &1.session_id)
    |> Enum.flat_map(fn {sid, session_links} ->
      build_session_entry(Map.get(sessions_by_id, sid), session_links)
    end)
    |> Enum.sort_by(
      &{-&1.max_confidence, &1.session.started_at || &1.session.inserted_at},
      :asc
    )
  end

  @doc """
  Loads file annotations for a project/path.
  """
  def load_file_annotations(project_id, relative_path) do
    ref_ids =
      AnnotationFileRef
      |> Ash.Query.filter(project_id == ^project_id and relative_path == ^relative_path)
      |> Ash.read!()
      |> Enum.map(& &1.annotation_id)
      |> Enum.uniq()

    if ref_ids == [] do
      []
    else
      Annotation
      |> Ash.Query.filter(id in ^ref_ids)
      |> Ash.Query.load([:message_refs, :file_refs])
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.read!()
    end
  end

  @doc """
  Loads messages for a given session (for transcript display).
  """
  def load_session_messages(session_id) do
    CommitDetail.load_session_messages(session_id)
  end

  @doc """
  Detects a language class from a file extension.
  """
  def language_class(relative_path) do
    relative_path
    |> Path.extname()
    |> String.trim_leading(".")
    |> ext_to_language()
  end

  @language_map %{
    "ex" => "elixir",
    "exs" => "elixir",
    "js" => "javascript",
    "ts" => "typescript",
    "tsx" => "typescript",
    "jsx" => "javascript",
    "py" => "python",
    "rb" => "ruby",
    "rs" => "rust",
    "go" => "go",
    "css" => "css",
    "html" => "html",
    "heex" => "html",
    "json" => "json",
    "md" => "markdown",
    "yaml" => "yaml",
    "yml" => "yaml",
    "sh" => "bash",
    "sql" => "sql"
  }

  defp load_session_links([]), do: []

  defp load_session_links(commit_ids) do
    SessionCommitLink
    |> Ash.Query.filter(commit_id in ^commit_ids)
    |> Ash.Query.sort(confidence: :desc)
    |> Ash.read!()
  end

  defp load_sessions_by_id([]), do: %{}

  defp load_sessions_by_id(links) do
    session_ids = links |> Enum.map(& &1.session_id) |> Enum.uniq()

    Session
    |> Ash.Query.filter(id in ^session_ids)
    |> Ash.read!()
    |> Map.new(&{&1.id, &1})
  end

  defp build_session_entry(nil, _links), do: []

  defp build_session_entry(session, links) do
    [
      %{
        session: session,
        link_types: links |> Enum.map(& &1.link_type) |> Enum.uniq(),
        max_confidence: links |> Enum.map(& &1.confidence) |> Enum.max(fn -> 0.0 end)
      }
    ]
  end

  defp ext_to_language(""), do: "plaintext"
  defp ext_to_language(ext), do: Map.get(@language_map, ext, ext)

  defp fetch_git_blob(project_id, relative_path) do
    sessions =
      Session
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.Query.sort(started_at: :desc)
      |> Ash.Query.limit(5)
      |> Ash.read!()

    cwd =
      sessions
      |> Enum.map(& &1.cwd)
      |> Enum.reject(&is_nil/1)
      |> Enum.find(&File.dir?/1)

    if cwd do
      case System.cmd("git", ["show", "HEAD:#{relative_path}"],
             cd: cwd,
             stderr_to_stdout: true
           ) do
        {output, 0} -> {:ok, output}
        _ -> {:error, :not_available}
      end
    else
      {:error, :not_available}
    end
  end
end
