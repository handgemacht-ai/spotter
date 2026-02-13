defmodule Spotter.Services.FileDetail do
  @moduledoc "Data service for the file detail page."

  alias Spotter.Services.CommitDetail

  alias Spotter.Transcripts.{
    Annotation,
    AnnotationFileRef,
    Commit,
    CommitFile,
    Session,
    SessionCommitLink
  }

  require Ash.Query
  require OpenTelemetry.Tracer

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
  Resolves the git repo root for a project by finding a valid session cwd on disk.

  Returns `{:ok, repo_root}` or `{:error, reason}`.
  """
  def resolve_repo_root(project_id) do
    OpenTelemetry.Tracer.with_span "spotter.file_detail.resolve_repo_root" do
      sessions =
        Session
        |> Ash.Query.filter(project_id == ^project_id and not is_nil(cwd))
        |> Ash.Query.sort(started_at: :desc)
        |> Ash.Query.limit(10)
        |> Ash.read!()

      cwd =
        sessions
        |> Enum.map(& &1.cwd)
        |> Enum.find(&File.dir?/1)

      case cwd do
        nil ->
          OpenTelemetry.Tracer.set_status(:error, "no_accessible_cwd")
          {:error, :no_accessible_cwd}

        cwd ->
          case System.cmd("git", ["-C", cwd, "rev-parse", "--show-toplevel"],
                 stderr_to_stdout: true
               ) do
            {root, 0} ->
              {:ok, String.trim(root)}

            {output, _} ->
              OpenTelemetry.Tracer.set_status(:error, "git_root_failed")

              OpenTelemetry.Tracer.set_attribute("git.error", String.slice(output, 0, 200))

              {:error, :git_root_failed}
          end
      end
    end
  end

  @doc """
  Loads file content by reading directly from the working tree on disk.

  Returns `{:ok, content}` or `{:error, reason}`.
  """
  def load_file_content(project_id, relative_path) do
    OpenTelemetry.Tracer.with_span "spotter.file_detail.load_file_content",
                                   %{attributes: %{"file.relative_path" => relative_path}} do
      case resolve_repo_root(project_id) do
        {:ok, repo_root} ->
          full_path = Path.join(repo_root, relative_path)

          case File.read(full_path) do
            {:ok, content} ->
              {:ok, content}

            {:error, reason} ->
              OpenTelemetry.Tracer.set_status(:error, "file_read_failed")
              OpenTelemetry.Tracer.set_attribute("file.error", inspect(reason))
              {:error, {:file_read_failed, reason, full_path}}
          end

        {:error, reason} ->
          {:error, reason}
      end
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
end
