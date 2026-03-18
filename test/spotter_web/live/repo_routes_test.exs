defmodule SpotterWeb.RepoRoutesTest do
  use Spotter.DataCase, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Spotter.Transcripts.Project

  @moduletag timeout: 30_000
  @endpoint SpotterWeb.Endpoint

  describe "repo routes" do
    test "/repo route resolves to RepoLive" do
      {:ok, _view, html} = live(build_conn(), "/repo")

      assert html =~ "Repository"
    end

    test "/repo with path segments resolves to RepoLive" do
      {:ok, _view, html} = live(build_conn(), "/repo/.claude/skills")

      assert html =~ "Repository"
    end
  end

  describe "folder view routes" do
    setup do
      project = Ash.create!(Project, %{name: "folder_route_test", pattern: "^folder_route"})
      %{project: project}
    end

    test "/projects/:project_id/folders/*folder_path resolves to FolderViewLive", %{
      project: project
    } do
      {:ok, _view, html} =
        live(build_conn(), "/projects/#{project.id}/folders/.claude/skills/product")

      assert html =~ ".claude/skills/product"
    end
  end
end
