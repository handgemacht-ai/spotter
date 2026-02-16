defmodule Spotter.Services.CommitHistory do
  @moduledoc "Aggregation service for the global commit history page."

  alias Spotter.Transcripts.{Commit, Project, Session, SessionCommitLink}

  require Ash.Query

  @default_limit 50
  @max_limit 50

  @doc """
  Returns paged commit rows with associated session entries.

  ## Filters
  - `:project_id` - filter to commits with linked sessions in this project
  - `:branch` - filter to commits on this branch

  ## Page options
  - `:limit` - max results per page (default/max 50)
  - `:after` - cursor string for next page
  """
  def list_commits_with_sessions(filters \\ %{}, page_opts \\ %{}) do
    limit = min(page_opts[:limit] || @default_limit, @max_limit)
    cursor = page_opts[:after]
    project_id = filters[:project_id]
    branch = filters[:branch]

    commits = load_commits(branch)
    scoped = scope_commits_to_project(commits, project_id)
    sorted = sort_commits(scoped)
    after_cursor = apply_cursor(sorted, cursor)
    {page, has_more} = paginate(after_cursor, limit)
    rows = build_rows(page, project_id)
    next_cursor = if has_more && page != [], do: encode_cursor(List.last(page)), else: nil

    %{rows: rows, has_more: has_more, cursor: next_cursor}
  end

  @doc """
  Returns filter options for the history page.

  - `:projects` - all projects sorted by name ascending
  - `:branches` - distinct non-empty branch values from commits, sorted ascending
  - `:default_branch` - computed default branch (main > master > most frequent > nil)
  """
  def list_filter_options do
    projects = Project |> Ash.Query.sort(name: :asc) |> Ash.read!()

    commits = Commit |> Ash.Query.select([:git_branch]) |> Ash.read!()

    branches =
      commits
      |> Enum.map(& &1.git_branch)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()
      |> Enum.sort()

    default_branch = compute_default_branch(branches, commits)

    %{projects: projects, branches: branches, default_branch: default_branch}
  end

  # -- Private helpers -------------------------------------------------------

  defp compute_default_branch(branches, commits) do
    cond do
      "main" in branches -> "main"
      "master" in branches -> "master"
      branches == [] -> nil
      true -> most_frequent_branch(commits)
    end
  end

  defp most_frequent_branch(commits) do
    commits
    |> Enum.map(& &1.git_branch)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.frequencies()
    |> Enum.sort_by(fn {branch, count} -> {-count, branch} end)
    |> List.first()
    |> elem(0)
  end

  defp load_commits(branch) do
    query = Commit

    query =
      if branch do
        Ash.Query.filter(query, git_branch == ^branch)
      else
        query
      end

    Ash.read!(query)
  end

  defp scope_commits_to_project(commits, nil), do: commits

  defp scope_commits_to_project(commits, project_id) do
    project_session_ids =
      Session
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.Query.select([:id])
      |> Ash.read!()
      |> MapSet.new(& &1.id)

    commit_ids = Enum.map(commits, & &1.id)

    linked_commit_ids =
      SessionCommitLink
      |> Ash.Query.filter(commit_id in ^commit_ids)
      |> Ash.Query.select([:commit_id, :session_id])
      |> Ash.read!()
      |> Enum.filter(&MapSet.member?(project_session_ids, &1.session_id))
      |> MapSet.new(& &1.commit_id)

    Enum.filter(commits, &MapSet.member?(linked_commit_ids, &1.id))
  end

  defp sort_commits(commits) do
    Enum.sort(commits, fn a, b ->
      a_date = a.committed_at || a.inserted_at
      b_date = b.committed_at || b.inserted_at

      case DateTime.compare(a_date, b_date) do
        :gt -> true
        :lt -> false
        :eq -> a.id >= b.id
      end
    end)
  end

  defp apply_cursor(commits, nil), do: commits

  defp apply_cursor(commits, cursor) do
    {cursor_date, cursor_id} = decode_cursor(cursor)

    Enum.drop_while(commits, fn c ->
      sort_date = c.committed_at || c.inserted_at

      case DateTime.compare(sort_date, cursor_date) do
        :gt -> true
        :lt -> false
        :eq -> c.id >= cursor_id
      end
    end)
  end

  defp paginate(items, limit) do
    taken = Enum.take(items, limit + 1)
    has_more = length(taken) > limit
    {Enum.take(taken, limit), has_more}
  end

  defp build_rows(commits, project_id) do
    commit_ids = Enum.map(commits, & &1.id)

    links =
      SessionCommitLink
      |> Ash.Query.filter(commit_id in ^commit_ids)
      |> Ash.read!()

    links = filter_links_by_project(links, project_id)

    sessions_by_id = load_sessions_map(links)
    projects_by_id = load_projects_map(sessions_by_id)
    links_by_commit = Enum.group_by(links, & &1.commit_id)

    commits
    |> Enum.map(fn commit ->
      session_entries =
        links_by_commit
        |> Map.get(commit.id, [])
        |> Enum.group_by(& &1.session_id)
        |> Enum.map(fn {session_id, session_links} ->
          session = Map.get(sessions_by_id, session_id)
          project = session && Map.get(projects_by_id, session.project_id)

          %{
            session: session,
            project: project,
            link_types: session_links |> Enum.map(& &1.link_type) |> Enum.uniq() |> Enum.sort(),
            max_confidence: session_links |> Enum.map(& &1.confidence) |> Enum.max()
          }
        end)
        |> Enum.sort_by(& &1.max_confidence, :desc)

      %{commit: commit, sessions: session_entries}
    end)
  end

  defp filter_links_by_project(links, nil), do: links

  defp filter_links_by_project(links, project_id) do
    project_session_ids =
      Session
      |> Ash.Query.filter(project_id == ^project_id)
      |> Ash.Query.select([:id])
      |> Ash.read!()
      |> MapSet.new(& &1.id)

    Enum.filter(links, &MapSet.member?(project_session_ids, &1.session_id))
  end

  defp load_sessions_map(links) do
    session_ids = links |> Enum.map(& &1.session_id) |> Enum.uniq()

    Session
    |> Ash.Query.filter(id in ^session_ids)
    |> Ash.read!()
    |> Map.new(&{&1.id, &1})
  end

  defp load_projects_map(sessions_by_id) do
    project_ids = sessions_by_id |> Map.values() |> Enum.map(& &1.project_id) |> Enum.uniq()

    Project
    |> Ash.Query.filter(id in ^project_ids)
    |> Ash.read!()
    |> Map.new(&{&1.id, &1})
  end

  defp encode_cursor(commit) do
    sort_date = commit.committed_at || commit.inserted_at

    %{"d" => DateTime.to_iso8601(sort_date), "id" => commit.id}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp decode_cursor(cursor) do
    %{"d" => date_str, "id" => id} =
      cursor
      |> Base.url_decode64!(padding: false)
      |> Jason.decode!()

    {:ok, date, _} = DateTime.from_iso8601(date_str)
    {date, id}
  end
end
