defmodule Spotter.Services.ProjectPeriodRollupPack do
  @moduledoc "Builds a deterministic input pack for a project period summary."

  @doc """
  Builds a pack from a project and its qualifying sessions for a bucket.

  `sessions` should already be filtered to qualifying sessions with commit data attached.
  Each session map should have: `:session_id`, `:hook_ended_at`, `:commit_hashes`, `:distilled_summary`.
  """
  def build(project, sessions, opts \\ []) do
    bucket_kind = Keyword.fetch!(opts, :bucket_kind)
    bucket_start_date = Keyword.fetch!(opts, :bucket_start_date)

    %{
      project: %{
        id: project.id,
        name: project.name,
        timezone: project.timezone,
        default_branch: Keyword.get(opts, :default_branch, "main")
      },
      bucket: %{
        bucket_kind: bucket_kind,
        bucket_start_date: to_string(bucket_start_date)
      },
      sessions:
        Enum.map(sessions, fn s ->
          %{
            session_id: s.session_id,
            hook_ended_at: s.hook_ended_at,
            commit_hashes: s.commit_hashes,
            distilled_summary: s.distilled_summary
          }
        end)
    }
  end
end
