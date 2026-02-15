defmodule Spotter.Transcripts.ConfigTest do
  use Spotter.DataCase

  alias Spotter.Transcripts.Config
  alias Spotter.Transcripts.Project

  describe "read!/0" do
    test "reads and parses spotter.toml" do
      config = Config.read!()

      assert %{transcripts_dir: dir, projects: projects} = config
      assert is_binary(dir)
      assert not String.contains?(dir, "~")
      assert map_size(projects) > 0

      {_name, project} = Enum.at(projects, 0)
      assert %{pattern: %Regex{}} = project
    end
  end

  describe "read!/0 projects from DB" do
    test "returns DB projects when they exist" do
      Ash.create!(Project, %{name: "my-project", pattern: "^my-project"})

      config = Config.read!()

      assert Map.has_key?(config.projects, "my-project")
      assert %{pattern: %Regex{}} = config.projects["my-project"]
    end

    test "returns TOML projects when DB is empty" do
      config = Config.read!()

      assert map_size(config.projects) > 0

      Enum.each(config.projects, fn {_name, %{pattern: pattern}} ->
        assert %Regex{} = pattern
      end)
    end
  end

  describe "read!/0 transcripts_dir" do
    test "returns a string path" do
      config = Config.read!()

      assert is_binary(config.transcripts_dir)
      refute String.starts_with?(config.transcripts_dir, "~")
    end
  end

  describe "import_projects_from_toml!/0" do
    test "imports TOML projects and makes DB authoritative" do
      toml_names = Config.read!().projects |> Map.keys()

      assert {:ok, count} = Config.import_projects_from_toml!()
      assert count > 0
      assert count == length(toml_names)

      # Now DB has projects, so read! should use them
      config = Config.read!()

      Enum.each(toml_names, fn name ->
        assert Map.has_key?(config.projects, name)
      end)
    end

    test "upserts on repeated import" do
      {:ok, first_count} = Config.import_projects_from_toml!()
      {:ok, second_count} = Config.import_projects_from_toml!()

      assert first_count == second_count

      # No duplicates created
      all_projects = Ash.read!(Project)
      names = Enum.map(all_projects, & &1.name)
      assert names == Enum.uniq(names)
    end
  end
end
