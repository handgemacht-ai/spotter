defmodule Spotter.Services.SessionDistillationPack do
  @moduledoc """
  Builds a deterministic input pack from a session for distillation.

  The pack is a structured map containing session metadata, linked commits,
  tool call stats, file snapshots, errors, and a transcript slice.
  """

  alias Spotter.Services.WaitingSummary.SliceBuilder
  alias Spotter.Transcripts.{Commit, FileSnapshot, Message, SessionCommitLink, ToolCall}

  require Ash.Query

  @default_char_budget 30_000
  @max_file_snapshots 50
  @max_errors 25
  @max_tool_call_names 25

  @doc """
  Builds a distillation pack for the given session.

  Options:
    - `:char_budget` - character budget for transcript slicing (default: 30_000)
  """
  def build(session, opts \\ []) do
    budget = Keyword.get(opts, :char_budget, configured_budget())
    commits = load_linked_commits(session)
    tool_calls = load_tool_calls(session)
    errors = tool_calls |> Enum.filter(& &1.is_error) |> Enum.take(@max_errors)
    file_snapshots = load_file_snapshots(session)
    {sliced_messages, _meta} = load_transcript_slice(session, budget)

    %{
      session: %{
        session_id: session.session_id,
        slug: session.slug,
        cwd: session.cwd,
        git_branch: session.git_branch,
        started_at: session.started_at,
        hook_ended_at: session.hook_ended_at,
        ended_at: session.ended_at,
        message_count: session.message_count,
        project_id: session.project_id
      },
      commits:
        Enum.map(commits, fn c ->
          %{
            git_branch: c.git_branch,
            subject: c.subject,
            body: c.body,
            authored_at: c.authored_at,
            committed_at: c.committed_at
          }
        end),
      tool_calls: aggregate_tool_calls(tool_calls),
      stats: %{
        messages_total: session.message_count || 0,
        tool_calls_total: length(tool_calls),
        tool_calls_failed: length(errors)
      },
      file_snapshots:
        Enum.map(file_snapshots, fn fs ->
          %{relative_path: fs.relative_path, change_type: fs.change_type, timestamp: fs.timestamp}
        end),
      errors:
        Enum.map(errors, fn e ->
          %{tool_name: e.tool_name, error_content: e.error_content}
        end),
      transcript_slice: build_transcript_text(sliced_messages)
    }
  end

  defp aggregate_tool_calls(tool_calls) do
    by_name =
      tool_calls
      |> Enum.frequencies_by(& &1.tool_name)
      |> Enum.map(fn {name, count} -> %{"tool_name" => name, "count" => count} end)
      |> Enum.sort_by(fn %{"count" => c, "tool_name" => n} -> {-c, n} end)
      |> Enum.take(@max_tool_call_names)

    %{total: length(tool_calls), by_name: by_name}
  end

  defp load_linked_commits(session) do
    links =
      SessionCommitLink
      |> Ash.Query.filter(session_id == ^session.id)
      |> Ash.read!()

    commit_ids = Enum.map(links, & &1.commit_id)

    if commit_ids == [] do
      []
    else
      Commit
      |> Ash.Query.filter(id in ^commit_ids)
      |> Ash.Query.sort(committed_at: :desc)
      |> Ash.read!()
    end
  end

  defp load_tool_calls(session) do
    ToolCall
    |> Ash.Query.filter(session_id == ^session.id)
    |> Ash.read!()
  end

  defp load_file_snapshots(session) do
    FileSnapshot
    |> Ash.Query.filter(session_id == ^session.id)
    |> Ash.Query.sort(timestamp: :desc)
    |> Ash.Query.limit(@max_file_snapshots)
    |> Ash.read!()
  rescue
    _ -> []
  end

  defp load_transcript_slice(session, budget) do
    messages =
      Message
      |> Ash.Query.filter(session_id == ^session.id and is_nil(subagent_id))
      |> Ash.Query.sort(timestamp: :asc)
      |> Ash.read!()
      |> Enum.map(fn msg ->
        %{
          role: msg.role,
          type: msg.type,
          content: msg.content
        }
      end)

    SliceBuilder.build(messages, budget: budget)
  end

  defp build_transcript_text(messages) do
    Enum.map_join(messages, "\n", &SliceBuilder.message_text/1)
  end

  defp configured_budget do
    case System.get_env("SPOTTER_SESSION_DISTILL_INPUT_CHAR_BUDGET") do
      nil -> @default_char_budget
      "" -> @default_char_budget
      val -> parse_int(val, @default_char_budget)
    end
  end

  defp parse_int(val, fallback) do
    case Integer.parse(String.trim(val)) do
      {int, ""} when int > 0 -> int
      _ -> fallback
    end
  end
end
