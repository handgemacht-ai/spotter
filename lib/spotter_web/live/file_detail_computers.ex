defmodule SpotterWeb.Live.FileDetailComputers do
  @moduledoc """
  AshComputer definitions for the file detail page.

  Provides reactive pipelines for file content, commits, linked sessions,
  annotations, and transcript rendering.
  """
  # credo:disable-for-this-file Credo.Check.Design.AliasUsage
  use AshComputer

  computer :file_detail do
    input :project_id do
      initial nil
    end

    input :relative_path do
      initial nil
    end

    input :selected_session_id do
      initial nil
    end

    input :view_mode do
      initial :blame
    end

    val :project do
      compute(fn
        %{project_id: nil} ->
          nil

        %{project_id: project_id} ->
          case Spotter.Services.FileDetail.load_project(project_id) do
            {:ok, project} -> project
            _ -> nil
          end
      end)

      depends_on([:project_id])
    end

    val :repo_root do
      compute(fn
        %{project: nil} ->
          nil

        %{project_id: project_id} ->
          case Spotter.Services.FileDetail.resolve_repo_root(project_id) do
            {:ok, root} -> root
            _ -> nil
          end
      end)

      depends_on([:project, :project_id])
    end

    val :file_content do
      compute(fn
        %{project: nil} ->
          nil

        %{project_id: _project_id, relative_path: nil} ->
          nil

        %{repo_root: nil} ->
          nil

        %{repo_root: repo_root, relative_path: relative_path} ->
          case File.read(Path.join(repo_root, relative_path)) do
            {:ok, content} -> content
            _ -> nil
          end
      end)

      depends_on([:project, :project_id, :relative_path, :repo_root])
    end

    val :blame_rows do
      compute(fn
        %{repo_root: nil} ->
          nil

        %{relative_path: nil} ->
          nil

        %{repo_root: repo_root, relative_path: relative_path} ->
          case Spotter.Services.FileBlame.load_blame(repo_root, relative_path) do
            {:ok, rows} -> rows
            _ -> nil
          end
      end)

      depends_on([:repo_root, :relative_path])
    end

    val :blame_error do
      compute(fn
        %{repo_root: nil} ->
          nil

        %{relative_path: nil} ->
          nil

        %{blame_rows: nil, repo_root: repo_root, relative_path: relative_path} ->
          case Spotter.Services.FileBlame.load_blame(repo_root, relative_path) do
            {:error, reason} -> reason
            _ -> nil
          end

        _ ->
          nil
      end)

      depends_on([:repo_root, :relative_path, :blame_rows])
    end

    val :file_error do
      compute(fn
        %{project: nil} ->
          nil

        %{relative_path: nil} ->
          nil

        %{project_id: project_id, repo_root: nil} ->
          case Spotter.Services.FileDetail.resolve_repo_root(project_id) do
            {:error, reason} -> reason
            _ -> nil
          end

        %{repo_root: repo_root, relative_path: relative_path, file_content: nil} ->
          full_path = Path.join(repo_root, relative_path)

          case File.read(full_path) do
            {:error, reason} -> {:file_read_failed, reason, full_path}
            _ -> nil
          end

        _ ->
          nil
      end)

      depends_on([:project, :project_id, :relative_path, :repo_root, :file_content])
    end

    val :language_class do
      compute(fn
        %{relative_path: nil} ->
          "plaintext"

        %{relative_path: relative_path} ->
          Spotter.Services.FileDetail.language_class(relative_path)
      end)

      depends_on([:relative_path])
    end

    val :commit_rows do
      compute(fn
        %{relative_path: nil} ->
          []

        %{relative_path: relative_path} ->
          Spotter.Services.FileDetail.load_commits_for_file(relative_path)
      end)

      depends_on([:relative_path])
    end

    val :linked_sessions do
      compute(fn
        %{relative_path: nil} ->
          []

        %{relative_path: relative_path} ->
          Spotter.Services.FileDetail.load_sessions_for_file(relative_path)
      end)

      depends_on([:relative_path])
    end

    val :annotation_rows do
      compute(fn
        %{project: nil} ->
          []

        %{project_id: project_id, relative_path: relative_path} ->
          Spotter.Services.FileDetail.load_file_annotations(project_id, relative_path)
      end)

      depends_on([:project, :project_id, :relative_path])
    end

    val :transcript_messages do
      compute(fn
        %{selected_session_id: nil} ->
          []

        %{selected_session_id: session_id} ->
          Spotter.Services.FileDetail.load_session_messages(session_id)
      end)

      depends_on([:selected_session_id])
    end

    val :transcript_rendered_lines do
      compute(fn %{
                   transcript_messages: messages,
                   linked_sessions: sessions,
                   selected_session_id: sid
                 } ->
        session_entry = Enum.find(sessions, &(&1.session.id == sid))
        cwd = if session_entry, do: session_entry.session.cwd
        opts = if cwd, do: [session_cwd: cwd], else: []
        Spotter.Services.TranscriptRenderer.render(messages, opts)
      end)

      depends_on([:transcript_messages, :linked_sessions, :selected_session_id])
    end

    val :not_found do
      compute(fn
        %{project: nil, project_id: pid} when not is_nil(pid) -> true
        _ -> false
      end)

      depends_on([:project, :project_id])
    end
  end
end
