defmodule Spotter.Transcripts.Config do
  @moduledoc """
  Reads and resolves transcript configuration.

  Uses DB-backed overrides (via `Spotter.Config.Runtime`) for `transcripts_dir`
  and DB-backed projects when available, falling back to `priv/spotter.toml`.
  """

  alias Spotter.Config.Runtime
  alias Spotter.Transcripts.Project

  require Ash.Query

  @config_path "priv/spotter.toml"

  @spec read!() :: %{
          transcripts_dir: String.t(),
          projects: %{String.t() => %{pattern: Regex.t()}}
        }
  def read! do
    {transcripts_dir, _source} = Runtime.transcripts_dir()
    projects = resolve_projects()

    %{transcripts_dir: transcripts_dir, projects: projects}
  end

  @doc """
  Imports projects from `priv/spotter.toml` into the DB.

  Returns `{:ok, count}` on success or `{:error, {:invalid_pattern, name}}`
  if any TOML pattern fails to compile.
  """
  @spec import_projects_from_toml!() ::
          {:ok, non_neg_integer()} | {:error, {:invalid_pattern, String.t()}}
  def import_projects_from_toml! do
    toml_projects = parse_toml_projects()

    with :ok <- validate_patterns(toml_projects) do
      count =
        Enum.reduce(toml_projects, 0, fn {name, %{"pattern" => pattern}}, acc ->
          upsert_project!(name, pattern)
          acc + 1
        end)

      {:ok, count}
    end
  end

  defp resolve_projects do
    case Ash.read!(Project) do
      [] -> parse_toml_project_regexes()
      db_projects -> db_projects_to_map(db_projects)
    end
  end

  defp db_projects_to_map(projects) do
    projects
    |> Enum.reject(&legacy_fallback_pattern?/1)
    |> Map.new(fn %Project{name: name, pattern: pattern} ->
      {name, %{pattern: Regex.compile!(pattern)}}
    end)
  end

  defp legacy_fallback_pattern?(%Project{pattern: pattern}) do
    String.trim(pattern) in [".*", "^.*$", "(?:.*)", "(?:^.*$)", ".*$"]
  end

  defp legacy_fallback_pattern?(_), do: false

  defp parse_toml_project_regexes do
    parse_toml_projects()
    |> Map.new(fn {name, config} ->
      {name, %{pattern: Regex.compile!(config["pattern"])}}
    end)
  end

  defp parse_toml_projects do
    path = Application.app_dir(:spotter, @config_path)

    path
    |> File.read!()
    |> Toml.decode!()
    |> Map.get("projects", %{})
  end

  defp validate_patterns(projects) do
    Enum.reduce_while(projects, :ok, fn {name, %{"pattern" => pattern}}, :ok ->
      case Regex.compile(pattern) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} -> {:halt, {:error, {:invalid_pattern, name}}}
      end
    end)
  end

  defp upsert_project!(name, pattern) do
    case Project
         |> Ash.Query.filter(name == ^name)
         |> Ash.read_one!() do
      nil -> Ash.create!(Project, %{name: name, pattern: pattern})
      existing -> Ash.update!(existing, %{pattern: pattern})
    end
  end
end
