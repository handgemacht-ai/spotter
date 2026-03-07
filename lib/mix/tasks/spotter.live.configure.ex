defmodule Mix.Tasks.Spotter.Live.Configure do
  @moduledoc """
  Configures Spotter for live container mode.

  Reads SPOTTER_LIVE_REPO_DIR and SPOTTER_LIVE_PROJECT_NAME from env,
  upserts the transcript_roots setting and a matching project.
  """
  @shortdoc "Configure Spotter for live container mode"
  use Mix.Task

  alias Spotter.Config.Setting
  alias Spotter.Transcripts.Project

  require Ash.Query

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    repo_dir = System.fetch_env!("SPOTTER_LIVE_REPO_DIR")
    project_name = System.fetch_env!("SPOTTER_LIVE_PROJECT_NAME")

    transcript_roots =
      case System.get_env("SPOTTER_LIVE_TRANSCRIPT_ROOTS") do
        nil ->
          home = System.user_home!()
          [Path.join(home, ".claude/projects"), Path.join(home, ".claude_agents/projects")]

        roots_str ->
          String.split(roots_str, ":", trim: true)
      end

    # Upsert transcript_roots setting
    upsert_setting("transcript_roots", Jason.encode!(transcript_roots))
    Mix.shell().info("transcript_roots = #{inspect(transcript_roots)}")

    # Convert repo path to transcript directory prefix and build a regex pattern.
    # Example: /workspace/myrepo -> ^\\-workspace\\-myrepo
    prefix = String.replace(repo_dir, "/", "-")
    pattern = "^" <> Regex.escape(prefix)

    upsert_project(project_name, pattern)
    Mix.shell().info("project = #{project_name}, pattern = #{pattern}")
  end

  defp upsert_setting(key, value) do
    case Setting |> Ash.Query.filter(key == ^key) |> Ash.read_one!() do
      nil -> Ash.create!(Setting, %{key: key, value: value})
      existing -> Ash.update!(existing, %{value: value})
    end
  end

  defp upsert_project(name, pattern) do
    case Project |> Ash.Query.filter(name == ^name) |> Ash.read_one!() do
      nil -> Ash.create!(Project, %{name: name, pattern: pattern})
      existing -> Ash.update!(existing, %{pattern: pattern})
    end
  end
end
