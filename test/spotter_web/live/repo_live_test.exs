defmodule SpotterWeb.RepoLiveTest do
  use Spotter.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Spotter.Transcripts.{Project, Session}

  @moduletag timeout: 30_000
  @endpoint SpotterWeb.Endpoint

  describe "mount renders tree" do
    setup do
      project = Ash.create!(Project, %{name: "repo-tree-test", pattern: "^repo-tree"})

      repo_root =
        Path.join(System.tmp_dir!(), "repo_live_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(repo_root)
      File.mkdir_p!(Path.join(repo_root, ".claude/skills/design"))
      File.write!(Path.join(repo_root, ".claude/skills/design/SKILL.md"), "# Design")
      File.mkdir_p!(Path.join(repo_root, "lib"))
      File.write!(Path.join(repo_root, "mix.exs"), "defmodule M do end")

      System.cmd("git", ["init"], cd: repo_root)

      _session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/test-sessions",
          cwd: repo_root,
          project_id: project.id
        })

      on_exit(fn -> File.rm_rf!(repo_root) end)

      %{project: project, repo_root: repo_root}
    end

    test "renders repo tree with directories and files", %{project: project} do
      {:ok, _view, html} = live(build_conn(), "/repo?project=#{project.id}")

      assert html =~ ~s(data-testid="repo-tree")
      assert html =~ "lib"
      assert html =~ "mix.exs"
    end

    test "detects skill folder badge on skill folder", %{project: project} do
      {:ok, _view, html} = live(build_conn(), "/repo?project=#{project.id}")

      assert html =~ "badge-skill"
      assert html =~ "SKILL"
    end

    test "renders directories before files", %{project: project} do
      {:ok, _view, html} = live(build_conn(), "/repo?project=#{project.id}")

      dir_pos = :binary.match(html, "repo-tree-folder") |> elem(0)
      file_pos = :binary.match(html, "repo-tree-file") |> elem(0)
      assert dir_pos < file_pos
    end
  end

  describe "toggle_folder" do
    setup do
      project = Ash.create!(Project, %{name: "repo-toggle-test", pattern: "^repo-toggle"})

      repo_root =
        Path.join(System.tmp_dir!(), "repo_toggle_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(repo_root)
      File.mkdir_p!(Path.join(repo_root, "a/b/c/deep"))
      File.write!(Path.join(repo_root, "a/b/c/deep/file.txt"), "content")
      File.mkdir_p!(Path.join(repo_root, "lib"))

      System.cmd("git", ["init"], cd: repo_root)

      _session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "/tmp/test-sessions",
          cwd: repo_root,
          project_id: project.id
        })

      on_exit(fn -> File.rm_rf!(repo_root) end)

      %{project: project, repo_root: repo_root}
    end

    test "collapsing an expanded folder hides its children", %{project: project} do
      {:ok, view, html} = live(build_conn(), "/repo?project=#{project.id}")

      assert html =~ ~s(data-path="a")
      assert html =~ ~s(data-path="a/b")

      html =
        view |> element(~s([data-testid="repo-tree-folder"][data-path="a"])) |> render_click()

      refute html =~ ~s(data-path="a/b")
    end
  end

  describe "empty state" do
    test "shows no-project message when no project selected" do
      {:ok, _view, html} = live(build_conn(), "/repo")

      assert html =~ ~s(data-testid="repo-no-project")
      assert html =~ "Select a project"
    end

    test "shows no-repo message when project has no repo root" do
      project = Ash.create!(Project, %{name: "no-repo-test", pattern: "^no-repo"})
      {:ok, _view, html} = live(build_conn(), "/repo?project=#{project.id}")

      assert html =~ ~s(data-testid="repo-empty")
      assert html =~ "No repository found"
    end
  end
end
