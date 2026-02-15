defmodule Mix.Tasks.Spotter.Live.ConfigureTest do
  use Spotter.DataCase, async: true

  alias Mix.Tasks.Spotter.Live.Configure
  alias Spotter.Config.Setting
  alias Spotter.Transcripts.Project

  require Ash.Query

  describe "run/1" do
    test "creates project with escaped pattern from repo dir" do
      System.put_env("SPOTTER_LIVE_REPO_DIR", "/workspace/myrepo")
      System.put_env("SPOTTER_LIVE_PROJECT_NAME", "myrepo")

      on_exit(fn ->
        System.delete_env("SPOTTER_LIVE_REPO_DIR")
        System.delete_env("SPOTTER_LIVE_PROJECT_NAME")
        System.delete_env("SPOTTER_LIVE_TRANSCRIPTS_DIR")
      end)

      Configure.run([])

      project = Project |> Ash.Query.filter(name == "myrepo") |> Ash.read_one!()
      assert project.pattern == "^\\-workspace\\-myrepo"
    end

    test "upserts transcripts_dir when SPOTTER_LIVE_TRANSCRIPTS_DIR is set" do
      System.put_env("SPOTTER_LIVE_REPO_DIR", "/workspace/myrepo")
      System.put_env("SPOTTER_LIVE_PROJECT_NAME", "myrepo")
      System.put_env("SPOTTER_LIVE_TRANSCRIPTS_DIR", "/custom/transcripts")

      on_exit(fn ->
        System.delete_env("SPOTTER_LIVE_REPO_DIR")
        System.delete_env("SPOTTER_LIVE_PROJECT_NAME")
        System.delete_env("SPOTTER_LIVE_TRANSCRIPTS_DIR")
      end)

      Configure.run([])

      setting = Setting |> Ash.Query.filter(key == "transcripts_dir") |> Ash.read_one!()
      assert setting.value == "/custom/transcripts"
    end
  end
end
