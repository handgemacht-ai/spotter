defmodule Spotter.Services.FileBlame do
  @moduledoc "Loads and parses git blame porcelain output for file detail."

  alias Spotter.Observability.ErrorReport
  alias Spotter.Transcripts.{Commit, SessionCommitLink}

  require Ash.Query
  require OpenTelemetry.Tracer

  @doc """
  Runs git blame and returns parsed rows with commit/session linkage.

  Returns `{:ok, rows}` or `{:error, reason}`.
  Each row is a map with: line_no, commit_hash, author, summary, text, commit_id, session_link.
  """
  def load_blame(repo_root, relative_path) do
    OpenTelemetry.Tracer.with_span "spotter.file_blame.load_blame",
                                   %{attributes: %{"file.relative_path" => relative_path}} do
      case run_git_blame(repo_root, relative_path) do
        {:ok, output} ->
          rows = parse_porcelain(output)
          rows = enrich_with_db_links(rows)
          {:ok, rows}

        {:error, reason} ->
          ErrorReport.set_trace_error("blame_failed", "blame_failed", "services.file_blame")
          {:error, reason}
      end
    end
  end

  defp run_git_blame(repo_root, relative_path) do
    case System.cmd(
           "git",
           ["-C", repo_root, "blame", "--line-porcelain", "HEAD", "--", relative_path],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {_, _code} -> {:error, :git_blame_failed}
    end
  end

  @doc """
  Parses git blame --line-porcelain output into a list of row maps.
  """
  def parse_porcelain(output) do
    output
    |> String.split("\n")
    |> parse_lines(%{}, [])
    |> Enum.reverse()
  end

  defp parse_lines([], _current, acc), do: acc

  defp parse_lines(["" | rest], current, acc) do
    parse_lines(rest, current, acc)
  end

  defp parse_lines([line | rest], current, acc) do
    cond do
      # Header line: <40-hex-hash> <orig_line> <final_line> [<num_lines>]
      Regex.match?(~r/^[0-9a-f]{40} /, line) ->
        [hash | parts] = String.split(line, " ")
        final_line = parts |> Enum.at(1, "0") |> String.to_integer()

        new_current = %{
          commit_hash: hash,
          line_no: final_line,
          author: Map.get(current, :author),
          summary: Map.get(current, :summary)
        }

        parse_lines(rest, new_current, acc)

      # Content line (tab-prefixed)
      String.starts_with?(line, "\t") ->
        text = String.slice(line, 1..-1//1)

        row = %{
          line_no: current[:line_no],
          commit_hash: current[:commit_hash],
          author: current[:author],
          summary: current[:summary],
          text: text
        }

        parse_lines(rest, current, [row | acc])

      # Metadata lines
      String.starts_with?(line, "author ") ->
        parse_lines(rest, Map.put(current, :author, String.trim_leading(line, "author ")), acc)

      String.starts_with?(line, "summary ") ->
        parse_lines(rest, Map.put(current, :summary, String.trim_leading(line, "summary ")), acc)

      true ->
        parse_lines(rest, current, acc)
    end
  end

  defp enrich_with_db_links(rows) do
    unique_hashes =
      rows
      |> Enum.map(& &1.commit_hash)
      |> Enum.uniq()

    # Upsert commits so we have DB IDs for linking
    commit_map = ensure_commits_exist(unique_hashes)

    # Load session links for all commit IDs
    commit_ids = Map.values(commit_map)
    session_map = load_best_sessions(commit_ids)

    Enum.map(rows, fn row ->
      commit_id = Map.get(commit_map, row.commit_hash)
      session_link = if commit_id, do: Map.get(session_map, commit_id)

      row
      |> Map.put(:commit_id, commit_id)
      |> Map.put(:session_link, session_link)
    end)
  end

  defp ensure_commits_exist(hashes) do
    # Bulk read existing commits
    existing =
      Commit
      |> Ash.Query.filter(commit_hash in ^hashes)
      |> Ash.read!()
      |> Map.new(&{&1.commit_hash, &1.id})

    missing = Enum.reject(hashes, &Map.has_key?(existing, &1))

    created =
      Enum.reduce(missing, %{}, fn hash, acc ->
        commit = Ash.create!(Commit, %{commit_hash: hash})
        Map.put(acc, hash, commit.id)
      end)

    Map.merge(existing, created)
  end

  defp load_best_sessions([]), do: %{}

  defp load_best_sessions(commit_ids) do
    links =
      SessionCommitLink
      |> Ash.Query.filter(commit_id in ^commit_ids)
      |> Ash.Query.load(:session)
      |> Ash.read!()

    links
    |> Enum.group_by(& &1.commit_id)
    |> Map.new(&best_session_for_commit/1)
  end

  defp best_session_for_commit({commit_id, commit_links}) do
    best =
      commit_links
      |> Enum.sort_by(&session_link_sort_key/1)
      |> List.first()

    session = best.session
    {commit_id, %{session_id: session.session_id, id: session.id}}
  end

  defp session_link_sort_key(link) do
    type_score = if link.link_type == :observed_in_session, do: 0, else: 1
    {type_score, -link.confidence, link.inserted_at}
  end
end
