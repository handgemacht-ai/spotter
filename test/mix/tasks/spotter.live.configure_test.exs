defmodule Mix.Tasks.Spotter.Live.ConfigureTest do
  use Spotter.DataCase, async: true

  alias Mix.Tasks.Spotter.Live.Configure
  alias Spotter.Config.Setting
  alias Spotter.Transcripts.Project

  require Ash.Query

  describe "run/1" do
    @tag :slow
    @tag timeout: 5_000
    test "creates project with escaped pattern from repo dir" do
      System.put_env("SPOTTER_LIVE_REPO_DIR", "/workspace/myrepo")
      System.put_env("SPOTTER_LIVE_PROJECT_NAME", "myrepo")

      on_exit(fn ->
        System.delete_env("SPOTTER_LIVE_REPO_DIR")
        System.delete_env("SPOTTER_LIVE_PROJECT_NAME")
        System.delete_env("SPOTTER_LIVE_TRANSCRIPT_ROOTS")
      end)

      Configure.run([])

      project = Project |> Ash.Query.filter(name == "myrepo") |> Ash.read_one!()
      assert project.pattern == "^\\-workspace\\-myrepo"
    end

    @tag :slow
    @tag timeout: 5_000
    test "upserts transcript_roots when SPOTTER_LIVE_TRANSCRIPT_ROOTS is set" do
      System.put_env("SPOTTER_LIVE_REPO_DIR", "/workspace/myrepo")
      System.put_env("SPOTTER_LIVE_PROJECT_NAME", "myrepo")
      System.put_env("SPOTTER_LIVE_TRANSCRIPT_ROOTS", "/custom/transcripts:/other/root")

      on_exit(fn ->
        System.delete_env("SPOTTER_LIVE_REPO_DIR")
        System.delete_env("SPOTTER_LIVE_PROJECT_NAME")
        System.delete_env("SPOTTER_LIVE_TRANSCRIPT_ROOTS")
      end)

      Configure.run([])

      setting = Setting |> Ash.Query.filter(key == "transcript_roots") |> Ash.read_one!()
      roots = Jason.decode!(setting.value)
      assert "/custom/transcripts" in roots
      assert "/other/root" in roots
    end
  end
end
