defmodule SpotterWeb.SidebarRepoLinkTest do
  use Spotter.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Spotter.Transcripts.Project

  @endpoint SpotterWeb.Endpoint

  describe "sidebar Repo nav link" do
    test "Repo link appears in sidebar navigation" do
      project = Ash.create!(Project, %{name: "repo_nav_test", pattern: "^repo_nav"})

      {:ok, _view, html} = live(build_conn(), "/?project=#{project.id}")

      assert html =~ "Repo"
      assert html =~ ~s(data-nav-path="/repo")
    end

    test "Repo link includes project param" do
      project = Ash.create!(Project, %{name: "repo_nav_test2", pattern: "^repo_nav2"})

      {:ok, _view, html} = live(build_conn(), "/?project=#{project.id}")

      assert html =~ "/repo?project=#{project.id}"
    end

    test "Repo link has alt-contains for folder routes" do
      project = Ash.create!(Project, %{name: "repo_nav_test3", pattern: "^repo_nav3"})

      {:ok, _view, html} = live(build_conn(), "/?project=#{project.id}")

      assert html =~ ~s(data-nav-path-alt-contains="/folders/")
    end
  end
end
