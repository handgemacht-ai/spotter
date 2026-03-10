defmodule SpotterWeb.Plugs.ProjectContextTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.Project
  alias SpotterWeb.Plugs.ProjectContext

  setup do
    Sandbox.checkout(Spotter.Repo)
    :ok
  end

  defp build_conn(query_string \\ "") do
    Phoenix.ConnTest.build_conn(:get, "/?" <> query_string)
    |> Plug.Conn.fetch_query_params()
  end

  defp call_plug(conn) do
    opts = ProjectContext.init([])
    ProjectContext.call(conn, opts)
  end

  describe "call/2 with valid project param" do
    test "assigns matching project_id when ?project= matches an existing project" do
      project_a = Ash.create!(Project, %{name: "alpha", pattern: "^alpha"})
      _project_b = Ash.create!(Project, %{name: "beta", pattern: "^beta"})

      conn = build_conn("project=#{project_a.id}") |> call_plug()

      assert conn.assigns[:current_project_id] == project_a.id
      assert is_list(conn.assigns[:projects])
      assert length(conn.assigns[:projects]) == 2
    end
  end

  describe "call/2 with invalid project param" do
    test "falls back to first project when ?project= does not match any project" do
      _project_a = Ash.create!(Project, %{name: "alpha", pattern: "^alpha"})
      _project_b = Ash.create!(Project, %{name: "beta", pattern: "^beta"})

      conn = build_conn("project=nonexistent-id") |> call_plug()

      # Should fall back to first project (sorted by name: alpha comes first)
      assert conn.assigns[:current_project_id] != nil
      assert conn.assigns[:current_project_id] != "nonexistent-id"
    end
  end

  describe "call/2 with no project param" do
    test "auto-selects first project when no param is provided" do
      _project_a = Ash.create!(Project, %{name: "alpha", pattern: "^alpha"})
      _project_b = Ash.create!(Project, %{name: "beta", pattern: "^beta"})

      conn = build_conn() |> call_plug()

      # Should auto-select the first project (sorted by name)
      assert conn.assigns[:current_project_id] != nil
      assert is_list(conn.assigns[:projects])
    end
  end

  describe "call/2 with empty projects" do
    test "assigns nil when no projects exist" do
      conn = build_conn() |> call_plug()

      assert conn.assigns[:current_project_id] == nil
      assert conn.assigns[:projects] == []
    end
  end

  describe "call/2 with project_id legacy param" do
    test "falls back to ?project_id= when ?project= is absent" do
      project_a = Ash.create!(Project, %{name: "alpha", pattern: "^alpha"})

      conn = build_conn("project_id=#{project_a.id}") |> call_plug()

      assert conn.assigns[:current_project_id] == project_a.id
    end
  end
end
