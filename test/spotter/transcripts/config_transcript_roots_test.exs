defmodule Spotter.Transcripts.ConfigTranscriptRootsTest do
  use Spotter.DataCase

  alias Spotter.Transcripts.Config

  describe "read!/0 returns transcript_roots" do
    test "returns %{transcript_roots: [...], projects: ...} shape" do
      config = Config.read!()

      assert %{transcript_roots: roots, projects: projects} = config
      assert is_list(roots)
      assert length(roots) >= 2
      assert is_map(projects)

      Enum.each(roots, fn root ->
        assert is_binary(root)
        refute String.starts_with?(root, "~")
      end)
    end

    test "no longer returns :transcripts_dir key" do
      config = Config.read!()

      refute Map.has_key?(config, :transcripts_dir)
    end
  end
end
