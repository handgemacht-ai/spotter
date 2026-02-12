defmodule Mix.Tasks.Spotter.E2e.Seed do
  @moduledoc """
  Seeds deterministic E2E transcript data into Spotter.
  """

  use Mix.Task

  alias Spotter.Repo
  alias Spotter.Transcripts.Config
  alias Spotter.Transcripts.Jobs.SyncTranscripts

  @shortdoc "Seed deterministic E2E transcripts from test fixtures"
  @fixture_project_dir "-home-marco-projects-spotter"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    config = Config.read!()
    fixture_root = fixture_root()
    target_dir = Path.join(config.transcripts_dir, @fixture_project_dir)

    before_counts = current_counts()
    copied_files = copy_fixtures!(fixture_root, target_dir)
    sync_projects!(config)
    after_counts = current_counts()

    Mix.shell().info("Seeded Spotter E2E transcripts")
    Mix.shell().info("  source: #{fixture_root}")
    Mix.shell().info("  target: #{target_dir}")
    Mix.shell().info("  copied_jsonl_files: #{copied_files}")
    Mix.shell().info("  sessions: #{before_counts.sessions} -> #{after_counts.sessions}")
    Mix.shell().info("  messages: #{before_counts.messages} -> #{after_counts.messages}")
    Mix.shell().info("  tool_calls: #{before_counts.tool_calls} -> #{after_counts.tool_calls}")
  end

  defp fixture_root do
    System.get_env("SPOTTER_E2E_FIXTURE_ROOT") ||
      Path.expand("test/fixtures/transcripts", File.cwd!())
  end

  defp copy_fixtures!(source_root, target_dir) do
    if !File.dir?(source_root) do
      Mix.raise("Fixture root not found: #{source_root}")
    end

    File.rm_rf!(target_dir)
    File.mkdir_p!(target_dir)

    source_root
    |> Path.join("**/*.jsonl")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce(0, fn source_file, acc ->
      rel_path = Path.relative_to(source_file, source_root)
      destination = Path.join(target_dir, rel_path)

      File.mkdir_p!(Path.dirname(destination))
      File.cp!(source_file, destination)

      acc + 1
    end)
  end

  defp sync_projects!(config) do
    run_id = Ash.UUID.generate()

    Enum.each(config.projects, fn {project_name, %{pattern: pattern}} ->
      job =
        struct(Oban.Job,
          args: %{
            "project_name" => project_name,
            "pattern" => Regex.source(pattern),
            "transcripts_dir" => config.transcripts_dir,
            "run_id" => run_id
          }
        )

      :ok = SyncTranscripts.perform(job)
    end)
  end

  defp current_counts do
    %{
      sessions: table_count!("sessions"),
      messages: table_count!("messages"),
      tool_calls: table_count!("tool_calls")
    }
  end

  defp table_count!(table) do
    %{rows: [[count]]} = Repo.query!("SELECT COUNT(*) FROM #{table}")
    count
  end
end
