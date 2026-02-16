defmodule Spotter.Transcripts.SessionsTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Project, Sessions}

  require Ash.Query

  setup do
    :ok = Sandbox.checkout(Spotter.Repo)
    Sandbox.mode(Spotter.Repo, {:shared, self()})
    :ok
  end

  defp create_project!(name, pattern) do
    Ash.create!(Project, %{name: name, pattern: pattern})
  end

  describe "find_or_create/2 with overlapping project patterns" do
    test "resolves todo2 correctly when todo pattern also matches" do
      create_project!("todo", "^-home-marco-projects-todo")
      create_project!("todo2", "^-home-marco-projects-todo2")

      session_id = Ash.UUID.generate()
      {:ok, session} = Sessions.find_or_create(session_id, cwd: "/home/marco/projects/todo2")

      project = Project |> Ash.Query.filter(id == ^session.project_id) |> Ash.read_one!()
      assert project.name == "todo2"
    end

    test "resolves todo correctly when todo2 pattern does not match" do
      create_project!("todo", "^-home-marco-projects-todo")
      create_project!("todo2", "^-home-marco-projects-todo2")

      session_id = Ash.UUID.generate()
      {:ok, session} = Sessions.find_or_create(session_id, cwd: "/home/marco/projects/todo")

      project = Project |> Ash.Query.filter(id == ^session.project_id) |> Ash.read_one!()
      assert project.name == "todo"
    end

    test "longest pattern wins regardless of insertion order" do
      # Insert the more specific pattern first
      create_project!("todo2", "^-home-marco-projects-todo2")
      create_project!("todo", "^-home-marco-projects-todo")

      session_id = Ash.UUID.generate()
      {:ok, session} = Sessions.find_or_create(session_id, cwd: "/home/marco/projects/todo2")

      project = Project |> Ash.Query.filter(id == ^session.project_id) |> Ash.read_one!()
      assert project.name == "todo2"
    end

    test "returns error when no pattern matches" do
      create_project!("todo", "^-home-marco-projects-todo")

      session_id = Ash.UUID.generate()

      assert {:error, {:project_not_found, "/home/marco/projects/unrelated"}} =
               Sessions.find_or_create(session_id, cwd: "/home/marco/projects/unrelated")
    end

    test "returns error when cwd is nil" do
      session_id = Ash.UUID.generate()
      assert {:error, :project_not_found} = Sessions.find_or_create(session_id)
    end

    test "single matching pattern is selected without ambiguity" do
      create_project!("spotter", "^-home-marco-projects-spotter")
      create_project!("todo", "^-home-marco-projects-todo")

      session_id = Ash.UUID.generate()
      {:ok, session} = Sessions.find_or_create(session_id, cwd: "/home/marco/projects/spotter")

      project = Project |> Ash.Query.filter(id == ^session.project_id) |> Ash.read_one!()
      assert project.name == "spotter"
    end

    test "deeply nested path resolves to most specific pattern" do
      create_project!("app", "^-home-marco-projects-app")
      create_project!("app-mobile", "^-home-marco-projects-app-mobile")

      session_id = Ash.UUID.generate()

      {:ok, session} =
        Sessions.find_or_create(session_id, cwd: "/home/marco/projects/app-mobile")

      project = Project |> Ash.Query.filter(id == ^session.project_id) |> Ash.read_one!()
      assert project.name == "app-mobile"
    end
  end
end
