defmodule Spotter.Services.SpecTestLinks do
  @moduledoc """
  Query helpers for loading spec-test link indices scoped by (project_id, commit_hash).

  Provides bidirectional lookups:
  - requirement -> linked test count
  - test -> linked requirement count
  """

  require Ash.Query

  alias Spotter.Transcripts.SpecTestLink

  @doc """
  Returns a map of `%{requirement_spec_key => count}` for the given project and commit.
  """
  @spec linked_test_counts(String.t(), String.t()) :: %{String.t() => non_neg_integer()}
  def linked_test_counts(project_id, commit_hash) do
    SpecTestLink
    |> Ash.Query.filter(project_id == ^project_id and commit_hash == ^commit_hash)
    |> Ash.read!()
    |> Enum.group_by(& &1.requirement_spec_key)
    |> Map.new(fn {key, links} -> {key, length(links)} end)
  rescue
    _ -> %{}
  end

  @doc """
  Returns a map of `%{test_key => count}` for the given project and commit.
  """
  @spec linked_requirement_counts(String.t(), String.t()) :: %{String.t() => non_neg_integer()}
  def linked_requirement_counts(project_id, commit_hash) do
    SpecTestLink
    |> Ash.Query.filter(project_id == ^project_id and commit_hash == ^commit_hash)
    |> Ash.read!()
    |> Enum.group_by(& &1.test_key)
    |> Map.new(fn {key, links} -> {key, length(links)} end)
  rescue
    _ -> %{}
  end
end
