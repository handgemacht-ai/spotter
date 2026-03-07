defmodule Spotter.Config.RuntimeTranscriptRootsTest do
  use Spotter.DataCase

  alias Spotter.Config.Runtime
  alias Spotter.Config.Setting

  describe "transcript_roots/0" do
    test "returns {paths, source} tuple with list of expanded paths" do
      {paths, source} = Runtime.transcript_roots()

      assert is_list(paths)
      assert length(paths) >= 2
      assert source in [:db, :toml, :default]

      Enum.each(paths, fn path ->
        assert is_binary(path)
        refute String.starts_with?(path, "~")
      end)
    end

    test "defaults include ~/.claude/projects and ~/.claude_agents/projects" do
      {paths, source} = Runtime.transcript_roots()
      assert source in [:toml, :default]

      home = System.user_home!()
      assert Path.join(home, ".claude/projects") in paths
      assert Path.join(home, ".claude_agents/projects") in paths
    end

    test "DB override replaces defaults with stored roots" do
      Ash.create!(Setting, %{
        key: "transcript_roots",
        value: ~s(["/custom/root1", "/custom/root2"])
      })

      {paths, :db} = Runtime.transcript_roots()

      assert "/custom/root1" in paths
      assert "/custom/root2" in paths
    end

    test "expands tilde in DB roots" do
      Ash.create!(Setting, %{key: "transcript_roots", value: ~s(["~/my-transcripts"])})

      {[path], :db} = Runtime.transcript_roots()

      refute String.starts_with?(path, "~")
      assert String.ends_with?(path, "/my-transcripts")
    end

    test "empty DB JSON array falls back to defaults" do
      Ash.create!(Setting, %{key: "transcript_roots", value: "[]"})

      {paths, source} = Runtime.transcript_roots()

      assert length(paths) >= 2
      assert source != :db
    end

    test "invalid DB JSON falls back to defaults" do
      Ash.create!(Setting, %{key: "transcript_roots", value: "not-json"})

      {paths, source} = Runtime.transcript_roots()

      assert is_list(paths)
      assert length(paths) >= 2
      assert source != :db
    end

    test "deduplicates paths" do
      Ash.create!(Setting, %{
        key: "transcript_roots",
        value: ~s(["/same/path", "/same/path", "/other"])
      })

      {paths, :db} = Runtime.transcript_roots()

      assert paths == Enum.uniq(paths)
      assert length(paths) == 2
    end

    test "expands relative paths" do
      Ash.create!(Setting, %{
        key: "transcript_roots",
        value: ~s(["relative/path"])
      })

      {[path], :db} = Runtime.transcript_roots()

      assert Path.type(path) == :absolute
    end
  end

  describe "Setting resource accepts transcript_roots key" do
    test "allows transcript_roots as a valid key" do
      assert {:ok, setting} =
               Ash.create(Setting, %{key: "transcript_roots", value: ~s(["/tmp/roots"])})

      assert setting.key == "transcript_roots"
    end

    test "rejects legacy transcripts_dir key" do
      assert {:error, _} = Ash.create(Setting, %{key: "transcripts_dir", value: "/old/path"})
    end
  end
end
