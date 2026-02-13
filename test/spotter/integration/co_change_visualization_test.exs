defmodule Spotter.Integration.CoChangeVisualizationTest do
  @moduledoc "Integration test ensuring CoChangeLive can render rows with provenance."

  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.CoChangeCalculator

  alias Spotter.TestSupport.GitRepoHelper

  alias Spotter.Transcripts.{
    CoChangeGroup,
    Project,
    Session
  }

  require Ash.Query

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    repo_path = GitRepoHelper.create_repo_with_history!()
    on_exit(fn -> File.rm_rf!(repo_path) end)
    %{repo_path: repo_path}
  end

  @tag timeout: 120_000
  test "LiveView renders groups with provenance data from persisted tables", %{
    repo_path: repo_path
  } do
    project =
      Ash.create!(Project, %{
        name: "viz-test-#{System.unique_integer([:positive])}",
        pattern: "^viz"
      })

    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "test-dir",
      project_id: project.id,
      cwd: repo_path
    })

    # Compute groups with provenance
    assert :ok = CoChangeCalculator.compute(project.id)

    # Verify groups exist
    groups =
      CoChangeGroup
      |> Ash.Query.filter(project_id == ^project.id and scope == :file)
      |> Ash.read!()

    assert groups != []

    # LiveView should render without crashes
    {:ok, view, html} = live(build_conn(), "/co-change?project_id=#{project.id}")
    assert html =~ "Co-change Groups"

    # Table should have rows
    [sample_group | _] = groups
    [sample_member | _] = sample_group.members
    assert html =~ sample_member

    # Expand a row - should show provenance sections without error
    html = render_click(view, "toggle_expand", %{"member" => sample_member})
    assert html =~ "Members"
    assert html =~ "Relevant Commits"
  end

  @tag timeout: 120_000
  test "LiveView renders without crash when provenance tables are empty" do
    project =
      Ash.create!(Project, %{
        name: "viz-empty-#{System.unique_integer([:positive])}",
        pattern: "^viz"
      })

    # Create a group manually without provenance
    Ash.create!(CoChangeGroup, %{
      project_id: project.id,
      scope: :file,
      group_key: "lib/a.ex|lib/b.ex",
      members: ["lib/a.ex", "lib/b.ex"],
      frequency_30d: 5,
      last_seen_at: ~U[2026-02-10 12:00:00Z]
    })

    {:ok, view, html} = live(build_conn(), "/co-change?project_id=#{project.id}")
    assert html =~ "lib/a.ex"

    # Expand - should show empty states
    html = render_click(view, "toggle_expand", %{"member" => "lib/a.ex"})
    assert html =~ "No file metrics available"
    assert html =~ "No commit provenance recorded"
  end
end
