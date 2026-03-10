defmodule SpotterWeb.InstructionsTelemetryLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.Project

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "instr-proj", pattern: "^instr-proj"})

    %{project: project}
  end

  describe "project context from on_mount" do
    test "uses current_project_id from on_mount, no project filter bar", %{project: project} do
      {:ok, _view, html} =
        live(build_conn(), "/telemetry/instructions?project=#{project.id}")

      # Content renders for the on_mount project
      assert html =~ project.name

      # No project filter bar — project selection is in the sidebar now
      refute html =~ "filter_project"
      refute html =~ "filter-label\">Project"
    end
  end
end
