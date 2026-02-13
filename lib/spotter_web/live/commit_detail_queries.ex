defmodule SpotterWeb.Live.CommitDetailQueries do
  @moduledoc false

  alias Spotter.Services.ProjectRollupBucket
  alias Spotter.Transcripts.{ProjectPeriodSummary, ProjectRollingSummary}

  require Ash.Query

  def load_rolling(project) do
    pid = project.id
    tz = project.timezone || "Etc/UTC"
    kind = ProjectRollupBucket.bucket_kind_from_env()

    ProjectRollingSummary
    |> Ash.Query.filter(
      project_id == ^pid and
        timezone == ^tz and
        bucket_kind == ^kind
    )
    |> Ash.Query.sort(computed_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> List.first()
  end

  def load_period(project, commit) do
    pid = project.id
    tz = project.timezone || "Etc/UTC"
    kind = ProjectRollupBucket.bucket_kind_from_env()
    commit_ts = commit.committed_at || commit.inserted_at
    bucket = ProjectRollupBucket.bucket_key(commit_ts, tz, kind)
    bsd = bucket.bucket_start_date

    ProjectPeriodSummary
    |> Ash.Query.filter(
      project_id == ^pid and
        timezone == ^tz and
        bucket_kind == ^kind and
        bucket_start_date == ^bsd
    )
    |> Ash.Query.sort(computed_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> List.first()
  end
end
