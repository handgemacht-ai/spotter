defmodule SpotterWeb.CoChangeLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{CoChangeGroup, Project}

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  defp create_group(project, opts) do
    Ash.create!(CoChangeGroup, %{
      project_id: project.id,
      scope: opts[:scope] || :file,
      group_key: opts[:group_key],
      members: opts[:members],
      frequency_30d: opts[:frequency] || 1,
      last_seen_at: opts[:last_seen_at] || ~U[2026-02-10 12:00:00Z]
    })
  end

  describe "global route" do
    test "renders co-change page at /co-change" do
      {:ok, _view, html} = live(build_conn(), "/co-change")

      assert html =~ "Co-change Groups"
    end

    test "shows select project prompt without project" do
      {:ok, _view, html} = live(build_conn(), "/co-change")

      assert html =~ "Select a project to view co-change groups"
    end

    test "renders with project filter via query param" do
      project = create_project("cochange-qp")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 5
      )

      {:ok, _view, html} = live(build_conn(), "/co-change?project_id=#{project.id}")

      assert html =~ "lib/a.ex"
      assert html =~ "lib/b.ex"
    end

    test "filter_project event navigates via push_patch" do
      project = create_project("cochange-filter")

      create_group(project,
        group_key: "lib/x.ex|lib/y.ex",
        members: ["lib/x.ex", "lib/y.ex"],
        frequency: 3
      )

      {:ok, view, _html} = live(build_conn(), "/co-change")

      html = render_click(view, "filter_project", %{"project-id" => project.id})

      assert html =~ "lib/x.ex"
    end
  end

  describe "project-scoped route" do
    test "renders rows sorted by max frequency" do
      project = create_project("cochange-pop")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 5
      )

      create_group(project,
        group_key: "lib/b.ex|lib/c.ex",
        members: ["lib/b.ex", "lib/c.ex"],
        frequency: 3
      )

      {:ok, _view, html} = live(build_conn(), "/projects/#{project.id}/co-change")

      assert html =~ "lib/a.ex"
      assert html =~ "lib/b.ex"
      assert html =~ "lib/c.ex"
      assert html =~ ~s(\u00d75)
      assert html =~ ~s(\u00d73)

      # b.ex should come first (max freq 5), then c.ex (max freq 3)
      b_pos = :binary.match(html, "lib/b.ex") |> elem(0)
      c_pos = :binary.match(html, "lib/c.ex") |> elem(0)
      assert b_pos < c_pos
    end
  end

  describe "directory scope toggle" do
    test "switches to directory scope on toggle" do
      project = create_project("cochange-dir")

      create_group(project,
        scope: :directory,
        group_key: "lib|test",
        members: ["lib", "test"],
        frequency: 8
      )

      {:ok, view, html} = live(build_conn(), "/projects/#{project.id}/co-change")

      # Initially file scope, no directory groups visible
      refute html =~ ~s(\u00d78)

      # Toggle to directory scope
      html = render_click(view, "toggle_scope", %{"scope" => "directory"})

      assert html =~ "lib"
      assert html =~ "test"
      assert html =~ ~s(\u00d78)
    end
  end

  describe "empty state" do
    test "renders empty message for project with no groups" do
      project = create_project("cochange-empty")

      {:ok, _view, html} = live(build_conn(), "/projects/#{project.id}/co-change")

      assert html =~ "No co-change groups for"
    end
  end

  describe "invalid project" do
    test "renders not found for invalid project id" do
      {:ok, _view, html} =
        live(build_conn(), "/projects/019c0000-0000-7000-8000-000000000000/co-change")

      assert html =~ "Project not found"
    end
  end

  describe "cross-links" do
    test "shows heatmap and hotspots links when project selected" do
      project = create_project("cochange-links")

      create_group(project,
        group_key: "lib/a.ex|lib/b.ex",
        members: ["lib/a.ex", "lib/b.ex"],
        frequency: 2
      )

      {:ok, _view, html} = live(build_conn(), "/co-change?project_id=#{project.id}")

      assert html =~ "Heatmap"
      assert html =~ "Hotspots"
    end
  end
end
