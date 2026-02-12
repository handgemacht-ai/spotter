defmodule Spotter.Services.CoChangeIntersections do
  @moduledoc """
  Pure set-intersection algorithm for computing co-change groups.

  Takes a list of commits (each with changed files) and returns groups of
  files or directories that frequently change together.
  """

  @binary_extensions ~w(.png .jpg .jpeg .gif .bmp .ico .svg .webp .woff .woff2 .ttf .eot .otf
    .pdf .zip .tar .gz .bz2 .7z .exe .dll .so .dylib .o .beam .ez .pyc .class .jar)

  @type commit :: %{hash: String.t(), timestamp: DateTime.t(), files: [String.t()]}
  @type group :: %{
          group_key: String.t(),
          members: [String.t()],
          frequency_30d: pos_integer(),
          last_seen_at: DateTime.t()
        }

  @doc """
  Compute co-change groups from a list of commits.

  Options:
    - `:scope` - `:file` (default) or `:directory`
  """
  @spec compute([commit()], keyword()) :: [group()]
  def compute(commits, opts \\ []) do
    scope = Keyword.get(opts, :scope, :file)

    commit_sets =
      commits
      |> Enum.map(fn commit ->
        members = normalize_members(commit.files, scope)
        %{members: members, timestamp: commit.timestamp}
      end)
      |> Enum.filter(fn %{members: members} -> MapSet.size(members) >= 2 end)

    if commit_sets == [] do
      []
    else
      candidates = build_candidates(commit_sets)
      scored = score_candidates(candidates, commit_sets)
      pruned = minimal_generator_prune(scored)
      sort_output(pruned)
    end
  end

  defp normalize_members(files, :file) do
    files
    |> Enum.reject(&binary_file?/1)
    |> MapSet.new()
  end

  defp normalize_members(files, :directory) do
    files
    |> Enum.map(fn file ->
      case Path.dirname(file) do
        "." -> "."
        dir -> dir
      end
    end)
    |> MapSet.new()
  end

  defp binary_file?(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext in @binary_extensions
  end

  defp build_candidates(commit_sets) do
    member_sets = Enum.map(commit_sets, & &1.members)

    intersections =
      member_sets
      |> pairs()
      |> Enum.map(fn {a, b} -> MapSet.intersection(a, b) end)
      |> Enum.filter(fn set -> MapSet.size(set) >= 2 end)
      |> Enum.uniq()

    # Expand: for each intersection larger than 2, add all size-2+ subsets
    intersections
    |> Enum.flat_map(&subsets_of_size_at_least_2/1)
    |> Enum.uniq()
  end

  defp subsets_of_size_at_least_2(set) do
    members = MapSet.to_list(set)
    size = length(members)

    if size <= 2 do
      [set]
    else
      for k <- 2..size,
          combo <- combinations(members, k),
          do: MapSet.new(combo)
    end
  end

  defp combinations(_list, 0), do: [[]]
  defp combinations([], _k), do: []

  defp combinations([head | tail], k) do
    with_head = for combo <- combinations(tail, k - 1), do: [head | combo]
    without_head = combinations(tail, k)
    with_head ++ without_head
  end

  defp pairs(list) do
    for {a, i} <- Enum.with_index(list),
        {b, j} <- Enum.with_index(list),
        i < j,
        do: {a, b}
  end

  defp score_candidates(candidates, commit_sets) do
    Enum.map(candidates, fn candidate ->
      supporting =
        Enum.filter(commit_sets, fn %{members: members} ->
          MapSet.subset?(candidate, members)
        end)

      frequency = length(supporting)
      last_seen = supporting |> Enum.map(& &1.timestamp) |> Enum.max(DateTime)
      sorted_members = candidate |> MapSet.to_list() |> Enum.sort()

      %{
        group_key: Enum.join(sorted_members, "|"),
        members: sorted_members,
        frequency_30d: frequency,
        last_seen_at: last_seen,
        _set: candidate
      }
    end)
  end

  defp minimal_generator_prune(scored) do
    scored
    |> Enum.reject(fn g ->
      Enum.any?(scored, fn h ->
        h != g and
          MapSet.subset?(h._set, g._set) and h._set != g._set and
          h.frequency_30d == g.frequency_30d
      end)
    end)
    |> Enum.map(&Map.delete(&1, :_set))
  end

  defp sort_output(groups) do
    Enum.sort_by(groups, fn g ->
      {-g.frequency_30d, -length(g.members), g.group_key}
    end)
  end
end
