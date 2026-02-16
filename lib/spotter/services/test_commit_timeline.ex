defmodule Spotter.Services.TestCommitTimeline do
  @moduledoc """
  Provides a project-scoped commit timeline with attached test run information.
  """

  alias Spotter.Services.CommitHistory
  alias Spotter.Transcripts.CommitTestRun

  require Ash.Query
  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Lists commits for a project with their associated test runs.

  ## Filters
  - `:project_id` (required) - UUID string
  - `:branch` - optional branch filter

  ## Page options
  - `:limit` - max results per page (default/max 50)
  - `:after` - cursor string for next page

  ## Return shape
      %{
        rows: [%{commit: %Commit{}, test_run: %CommitTestRun{} | nil}],
        cursor: cursor | nil,
        has_more: boolean
      }
  """
  @spec list(map(), map()) :: map()
  def list(filters \\ %{}, page_opts \\ %{}) do
    Tracer.with_span "spotter.test_commit_timeline.list" do
      project_id = Map.fetch!(filters, :project_id)
      Tracer.set_attribute("spotter.project_id", project_id)

      result = CommitHistory.list_commits_with_sessions(filters, page_opts)

      commit_ids = Enum.map(result.rows, & &1.commit.id)
      runs_by_commit_id = load_test_runs(project_id, commit_ids)

      rows =
        Enum.map(result.rows, fn row ->
          %{
            commit: row.commit,
            test_run: Map.get(runs_by_commit_id, row.commit.id)
          }
        end)

      %{rows: rows, cursor: result.cursor, has_more: result.has_more}
    end
  end

  defp load_test_runs(_project_id, []), do: %{}

  defp load_test_runs(project_id, commit_ids) do
    CommitTestRun
    |> Ash.Query.filter(project_id == ^project_id and commit_id in ^commit_ids)
    |> Ash.read!()
    |> Map.new(&{&1.commit_id, &1})
  end
end
