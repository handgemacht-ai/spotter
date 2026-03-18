defmodule SpotterWeb.DashboardSkillCardsTest do
  use Spotter.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Spotter.Transcripts.{Project, Session}

  @endpoint SpotterWeb.Endpoint

  setup do
    repo_root =
      Path.join(System.tmp_dir!(), "dash_cards_test_#{System.unique_integer([:positive])}")

    skill_dir = Path.join(repo_root, ".claude/skills/product")
    memory_dir = Path.join(repo_root, ".claude/agent-memory")
    File.mkdir_p!(skill_dir)
    File.mkdir_p!(memory_dir)
    File.write!(Path.join(skill_dir, "SKILL.md"), "# Product Skill")
    File.write!(Path.join(memory_dir, "user_role.md"), "# User Role")

    System.cmd("git", ["init"], cd: repo_root)

    project = Ash.create!(Project, %{name: "dash-cards-test", pattern: "^dash-cards"})

    _session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/dash-cards-sessions",
        cwd: repo_root,
        project_id: project.id,
        started_at: DateTime.utc_now()
      })

    on_exit(fn -> File.rm_rf!(repo_root) end)

    %{project: project, repo_root: repo_root}
  end

  describe "skill folder cards on dashboard" do
    test "renders folder cards when skill folders exist", %{project: project} do
      {:ok, _view, html} = live(build_conn(), "/?project=#{project.id}")

      assert html =~ "dashboard-card"
      assert html =~ "Product Skill"
      assert html =~ "Agent Memory"
    end

    test "cards link to folder view", %{project: project} do
      {:ok, _view, html} = live(build_conn(), "/?project=#{project.id}")

      assert html =~ "/projects/#{project.id}/folders/.claude/skills/product"
      assert html =~ "/projects/#{project.id}/folders/.claude/agent-memory"
    end

    test "renders data-folder-type attributes", %{project: project} do
      {:ok, _view, html} = live(build_conn(), "/?project=#{project.id}")

      assert html =~ ~s(data-folder-type="product_skill")
      assert html =~ ~s(data-folder-type="agent_memory")
    end

    test "renders dashboard-skill-cards container", %{project: project} do
      {:ok, _view, html} = live(build_conn(), "/?project=#{project.id}")

      assert html =~ ~s(data-testid="dashboard-skill-cards")
    end
  end

  describe "no skill folder cards" do
    test "no cards when project has no skill folders" do
      bare_root =
        Path.join(System.tmp_dir!(), "bare_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(bare_root)
      System.cmd("git", ["init"], cd: bare_root)

      project2 = Ash.create!(Project, %{name: "no-folders-test", pattern: "^no-folders"})

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "/tmp/bare-sessions",
        cwd: bare_root,
        project_id: project2.id,
        started_at: DateTime.utc_now()
      })

      {:ok, _view, html} = live(build_conn(), "/?project=#{project2.id}")

      refute html =~ "dashboard-card"
      refute html =~ ~s(data-testid="dashboard-skill-cards")

      File.rm_rf!(bare_root)
    end
  end
end
