defmodule SpotterWeb.Live.CommitDetailComputers do
  @moduledoc """
  AshComputer definitions for the commit detail page.

  Provides reactive pipelines for commit data, linked sessions,
  co-change overlaps, diff text, and transcript rendering.
  """
  # credo:disable-for-this-file Credo.Check.Design.AliasUsage
  use AshComputer

  computer :commit_detail do
    input :commit_id do
      initial nil
    end

    input :selected_session_id do
      initial nil
    end

    input :show_full_diff do
      initial false
    end

    val :commit do
      compute(fn
        %{commit_id: nil} ->
          nil

        %{commit_id: commit_id} ->
          case Spotter.Services.CommitDetail.load_commit(commit_id) do
            {:ok, commit} -> commit
            _ -> nil
          end
      end)

      depends_on([:commit_id])
    end

    val :linked_sessions do
      compute(fn
        %{commit: nil} ->
          []

        %{commit: commit} ->
          Spotter.Services.CommitDetail.load_linked_sessions(commit.id)
      end)

      depends_on([:commit])
    end

    val :project do
      compute(fn
        %{linked_sessions: []} ->
          nil

        %{linked_sessions: [entry | _]} ->
          try do
            Ash.get!(Spotter.Transcripts.Project, entry.session.project_id)
          rescue
            _ -> nil
          end
      end)

      depends_on([:linked_sessions])
    end

    val :rolling_summary do
      compute(fn
        %{project: nil} ->
          nil

        %{project: project} ->
          SpotterWeb.Live.CommitDetailQueries.load_rolling(project)
      end)

      depends_on([:project])
    end

    val :period_summary do
      compute(fn
        %{project: nil} ->
          nil

        %{commit: nil} ->
          nil

        %{project: project, commit: commit} ->
          SpotterWeb.Live.CommitDetailQueries.load_period(project, commit)
      end)

      depends_on([:project, :commit])
    end

    val :co_change_rows do
      compute(fn
        %{commit: nil} ->
          []

        %{commit: commit} ->
          Spotter.Services.CommitDetail.load_co_change_overlaps(commit)
      end)

      depends_on([:commit])
    end

    val :diff_text do
      compute(fn
        %{commit: nil} ->
          ""

        %{commit: commit, linked_sessions: sessions} ->
          Spotter.Services.CommitDetail.fetch_diff(commit, sessions)
      end)

      depends_on([:commit, :linked_sessions])
    end

    val :transcript_messages do
      compute(fn
        %{selected_session_id: nil} ->
          []

        %{selected_session_id: session_id, linked_sessions: sessions} ->
          session_entry = Enum.find(sessions, &(&1.session.id == session_id))

          if session_entry do
            Spotter.Services.CommitDetail.load_session_messages(session_entry.session.id)
          else
            []
          end
      end)

      depends_on([:selected_session_id, :linked_sessions])
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

    val :error_state do
      compute(fn
        %{commit_id: nil} -> :no_id
        %{commit: nil} -> :not_found
        _ -> nil
      end)

      depends_on([:commit_id, :commit])
    end
  end
end
