defmodule Spotter.Transcripts.ConfigTest do
  use ExUnit.Case, async: true

  alias Spotter.Transcripts.Config

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
end
