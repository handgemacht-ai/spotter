defmodule Spotter.Services.SessionCommitLinker do
  @moduledoc "Computes inferred session-commit links based on enriched commit metadata."

  alias Spotter.Transcripts.{Commit, SessionCommitLink}

  require Ash.Query

  @confidence %{
    descendant_of_observed: 0.90,
    patch_match: 0.85,
    file_overlap: 0.60
  }

  @min_confidence 0.60
  @min_jaccard 0.70
  @max_time_delta_minutes 360

  @doc """
  Given a session and its observed commits, compute inferred links
  for other commits that may be related.
  """
  def link_inferred(session, observed_commits) do
    observed_hashes = MapSet.new(observed_commits, & &1.commit_hash)
    session_files = session_changed_files(session)

    # Find descendant commits (children of observed)
    observed_commits
    |> Enum.flat_map(&find_descendants/1)
    |> Enum.reject(&MapSet.member?(observed_hashes, &1.commit_hash))
    |> Enum.uniq_by(& &1.commit_hash)
    |> Enum.each(fn commit ->
      create_link_if_better(session, commit, :descendant_of_observed, %{
        "parent_hashes" => commit.parent_hashes
      })
    end)

    # Find patch-id matches and file-overlap matches
    if Enum.any?(session_files) do
      find_nearby_commits(session, observed_hashes)
      |> Enum.each(fn commit ->
        maybe_link_by_file_overlap(session, commit, session_files)
      end)
    end

    :ok
  end

  defp session_changed_files(session) do
    observed_links =
      SessionCommitLink
      |> Ash.Query.filter(session_id == ^session.id and link_type == :observed_in_session)
      |> Ash.read!()

    commit_ids = Enum.map(observed_links, & &1.commit_id)

    Commit
    |> Ash.Query.filter(id in ^commit_ids)
    |> Ash.read!()
    |> Enum.flat_map(& &1.changed_files)
    |> MapSet.new()
  end

  defp find_descendants(commit) do
    Commit
    |> Ash.Query.filter(
      fragment("EXISTS (SELECT 1 FROM json_each(?) WHERE value = ?)", parent_hashes,
        commit_hash: ^commit.commit_hash
      )
    )
    |> Ash.read!()
  rescue
    _ -> []
  end

  defp find_nearby_commits(_session, observed_hashes) do
    cutoff = DateTime.add(DateTime.utc_now(), -@max_time_delta_minutes, :minute)

    Commit
    |> Ash.Query.filter(
      committed_at >= ^cutoff and commit_hash not in ^MapSet.to_list(observed_hashes)
    )
    |> Ash.read!()
  rescue
    _ -> []
  end

  defp maybe_link_by_file_overlap(session, commit, session_files) do
    commit_files = MapSet.new(commit.changed_files)
    intersection = MapSet.intersection(session_files, commit_files) |> MapSet.size()
    union = MapSet.union(session_files, commit_files) |> MapSet.size()

    jaccard = if union > 0, do: intersection / union, else: 0.0

    if jaccard >= @min_jaccard do
      create_link_if_better(session, commit, :file_overlap, %{
        "jaccard" => Float.round(jaccard, 3),
        "shared_files" => MapSet.intersection(session_files, commit_files) |> MapSet.to_list()
      })
    end
  end

  defp create_link_if_better(session, commit, link_type, evidence) do
    confidence = Map.fetch!(@confidence, link_type)

    if confidence >= @min_confidence do
      Ash.create(SessionCommitLink, %{
        session_id: session.id,
        commit_id: commit.id,
        link_type: link_type,
        confidence: confidence,
        evidence: evidence
      })
    end
  end
end
