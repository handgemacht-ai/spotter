defmodule Mix.Tasks.Spotter.E2e.Seed do
  @moduledoc """
  Seeds deterministic E2E transcript data into Spotter.

  ## Usage

      mix spotter.e2e.seed                                    # Seed all fixtures
      mix spotter.e2e.seed --scenario team-overlap             # Seed only team-overlap
      mix spotter.e2e.seed --cleanup                           # Clean up all scenario data
      mix spotter.e2e.seed --cleanup --scenario team-overlap   # Clean up team-overlap only
  """

  use Mix.Task

  alias Spotter.Repo
  alias Spotter.Transcripts.Config
  alias Spotter.Transcripts.Jobs.SyncTranscripts
  alias Spotter.Transcripts.Project

  require Ash.Query

  @shortdoc "Seed deterministic E2E transcripts from test fixtures"
  @fixture_project_dir "-home-marco-projects-spotter"
  @e2e_project_name "e2e-spotter"
  @e2e_project_pattern "^#{Regex.escape(@fixture_project_dir)}$"

  @scenarios %{
    "team-overlap" => %{
      subdir: "team-overlap",
      session_ids: [
        "00000000-0000-0000-0000-000000000001",
        "00000000-0000-0000-0000-000000000002",
        "00000000-0000-0000-0000-000000000003"
      ]
    }
  }

  # FK-safe delete order: deepest dependents first
  @cleanup_tables [
    "annotation_file_refs",
    "annotation_message_refs",
    "annotations",
    "tool_calls",
    "file_snapshots",
    "session_commit_links",
    "session_reworks",
    "subagents",
    "messages",
    "team_members"
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [scenario: :string, cleanup: :boolean],
        aliases: [s: :scenario, c: :cleanup]
      )

    scenario = Keyword.get(opts, :scenario)
    cleanup? = Keyword.get(opts, :cleanup, false)

    validate_scenario!(scenario)

    Mix.Task.run("app.start")

    if cleanup? do
      run_cleanup(scenario)
    else
      run_seed(scenario)
    end
  end

  defp run_seed(scenario) do
    fixture_root = fixture_root()
    ensure_e2e_project!()
    config = Config.read!()
    [first_root | _] = config.transcript_roots
    target_dir = Path.join(first_root, @fixture_project_dir)

    source_dir =
      case scenario do
        nil -> fixture_root
        name -> Path.join(fixture_root, @scenarios[name].subdir)
      end

    before_counts = current_counts()
    copied_files = copy_fixtures!(source_dir, target_dir, scenario)
    sync_projects!(config)
    after_counts = current_counts()

    label = scenario || "all"
    Mix.shell().info("Seeded Spotter E2E transcripts (scenario: #{label})")
    Mix.shell().info("  source: #{source_dir}")
    Mix.shell().info("  target: #{target_dir}")
    Mix.shell().info("  copied_jsonl_files: #{copied_files}")
    Mix.shell().info("  sessions: #{before_counts.sessions} -> #{after_counts.sessions}")
    Mix.shell().info("  messages: #{before_counts.messages} -> #{after_counts.messages}")
    Mix.shell().info("  tool_calls: #{before_counts.tool_calls} -> #{after_counts.tool_calls}")
  end

  defp run_cleanup(scenario) do
    session_ids = session_ids_for_cleanup(scenario)

    before_counts = current_counts()
    delete_seeded_data!(session_ids)
    after_counts = current_counts()

    label = scenario || "all"
    Mix.shell().info("Cleaned up Spotter E2E data (scenario: #{label})")
    Mix.shell().info("  session_ids: #{length(session_ids)}")
    Mix.shell().info("  sessions: #{before_counts.sessions} -> #{after_counts.sessions}")
    Mix.shell().info("  messages: #{before_counts.messages} -> #{after_counts.messages}")
    Mix.shell().info("  tool_calls: #{before_counts.tool_calls} -> #{after_counts.tool_calls}")
  end

  defp ensure_e2e_project! do
    case Project |> Ash.Query.filter(name == ^@e2e_project_name) |> Ash.read_one!() do
      nil -> Ash.create!(Project, %{name: @e2e_project_name, pattern: @e2e_project_pattern})
      existing -> Ash.update!(existing, %{pattern: @e2e_project_pattern})
    end
  end

  defp validate_scenario!(nil), do: :ok

  defp validate_scenario!(name) do
    unless Map.has_key?(@scenarios, name) do
      known = @scenarios |> Map.keys() |> Enum.join(", ")
      Mix.raise("Unknown scenario: #{name}. Known scenarios: #{known}")
    end
  end

  defp session_ids_for_cleanup(nil) do
    @scenarios
    |> Map.values()
    |> Enum.flat_map(& &1.session_ids)
    |> Enum.uniq()
  end

  defp session_ids_for_cleanup(name), do: @scenarios[name].session_ids

  defp delete_seeded_data!([]), do: :ok

  defp delete_seeded_data!(session_ids) do
    placeholders = Enum.map_join(1..length(session_ids), ", ", &"$#{&1}")

    # Delete from tables that reference annotations (which reference sessions)
    Repo.query!(
      "DELETE FROM annotation_file_refs WHERE annotation_id IN " <>
        "(SELECT id FROM annotations WHERE session_id IN " <>
        "(SELECT id FROM sessions WHERE session_id IN (#{placeholders})))",
      session_ids
    )

    Repo.query!(
      "DELETE FROM annotation_message_refs WHERE annotation_id IN " <>
        "(SELECT id FROM annotations WHERE session_id IN " <>
        "(SELECT id FROM sessions WHERE session_id IN (#{placeholders})))",
      session_ids
    )

    # Delete from tables that directly reference sessions via session FK
    for table <- @cleanup_tables -- ["annotation_file_refs", "annotation_message_refs"] do
      Repo.query!(
        "DELETE FROM #{table} WHERE session_id IN " <>
          "(SELECT id FROM sessions WHERE session_id IN (#{placeholders}))",
        session_ids
      )
    end

    # Delete the sessions themselves
    Repo.query!(
      "DELETE FROM sessions WHERE session_id IN (#{placeholders})",
      session_ids
    )

    # Delete orphaned teams that have no remaining members
    Repo.query!("DELETE FROM teams WHERE id NOT IN (SELECT DISTINCT team_id FROM team_members)")
  end

  defp fixture_root do
    System.get_env("SPOTTER_E2E_FIXTURE_ROOT") ||
      Path.expand("test/fixtures/transcripts", File.cwd!())
  end

  defp copy_fixtures!(source_dir, target_dir, _scenario) do
    unless File.dir?(source_dir) do
      Mix.raise("Fixture source not found: #{source_dir}")
    end

    File.rm_rf!(target_dir)
    File.mkdir_p!(target_dir)

    source_dir
    |> Path.join("**/*.jsonl")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce(0, fn source_file, acc ->
      rel_path = Path.relative_to(source_file, source_dir)
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
            "transcript_roots" => config.transcript_roots,
            "run_id" => run_id,
            "enqueue_downstream_jobs" => false
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
