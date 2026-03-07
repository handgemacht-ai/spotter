defmodule Mix.Tasks.Spotter.Live.ConfigureTest do
  use Spotter.DataCase, async: true

  alias Mix.Tasks.Spotter.Live.Configure
  alias Spotter.Config.Runtime
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

    @tag :slow
    @tag timeout: 5_000
    test "multi-root env var produces Runtime-parseable setting with all paths" do
      System.put_env("SPOTTER_LIVE_REPO_DIR", "/workspace/myrepo")
      System.put_env("SPOTTER_LIVE_PROJECT_NAME", "myrepo")
      System.put_env("SPOTTER_LIVE_TRANSCRIPT_ROOTS", "/alpha/transcripts:/beta/transcripts")

      on_exit(fn ->
        System.delete_env("SPOTTER_LIVE_REPO_DIR")
        System.delete_env("SPOTTER_LIVE_PROJECT_NAME")
        System.delete_env("SPOTTER_LIVE_TRANSCRIPT_ROOTS")
      end)

      Configure.run([])

      # Runtime must resolve from DB with both paths
      {roots, :db} = Runtime.transcript_roots()
      assert "/alpha/transcripts" in roots
      assert "/beta/transcripts" in roots
    end

    @tag :slow
    @tag timeout: 5_000
    test "default transcript_roots writes setting parseable by Runtime" do
      System.put_env("SPOTTER_LIVE_REPO_DIR", "/workspace/myrepo")
      System.put_env("SPOTTER_LIVE_PROJECT_NAME", "myrepo")
      System.delete_env("SPOTTER_LIVE_TRANSCRIPT_ROOTS")

      on_exit(fn ->
        System.delete_env("SPOTTER_LIVE_REPO_DIR")
        System.delete_env("SPOTTER_LIVE_PROJECT_NAME")
      end)

      Configure.run([])

      # Must write transcript_roots (not transcripts_dir)
      setting = Setting |> Ash.Query.filter(key == "transcript_roots") |> Ash.read_one!()
      assert setting != nil

      no_old_key = Setting |> Ash.Query.filter(key == "transcripts_dir") |> Ash.read_one!()
      assert no_old_key == nil

      # Value must be parseable by Runtime
      {roots, :db} = Runtime.transcript_roots()
      assert is_list(roots)
      assert roots != []
      assert Enum.all?(roots, &is_binary/1)
      # Default should include the user's .claude/projects
      assert Enum.any?(roots, &String.ends_with?(&1, ".claude/projects"))
    end

    @tag :slow
    @tag timeout: 5_000
    test "default transcript_roots includes both claude and claude_agents directories" do
      System.put_env("SPOTTER_LIVE_REPO_DIR", "/workspace/myrepo")
      System.put_env("SPOTTER_LIVE_PROJECT_NAME", "myrepo")
      System.delete_env("SPOTTER_LIVE_TRANSCRIPT_ROOTS")

      on_exit(fn ->
        System.delete_env("SPOTTER_LIVE_REPO_DIR")
        System.delete_env("SPOTTER_LIVE_PROJECT_NAME")
      end)

      Configure.run([])

      setting = Setting |> Ash.Query.filter(key == "transcript_roots") |> Ash.read_one!()
      roots = Jason.decode!(setting.value)

      # Default must match Runtime.@default_transcript_roots:
      # both ~/.claude/projects AND ~/.claude_agents/projects
      assert Enum.any?(roots, &String.ends_with?(&1, ".claude/projects"))
      assert Enum.any?(roots, &String.ends_with?(&1, ".claude_agents/projects"))
    end
  end
end
