defmodule Spotter.Transcripts.Jobs.ComputeCoChangeTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{CoChangeGroup, Project}
  alias Spotter.Transcripts.Jobs.ComputeCoChange

  require Ash.Query

  setup do
    Sandbox.checkout(Repo)
  end

  defp create_project(name) do
    Ash.create!(Project, %{name: name, pattern: "^#{name}"})
  end

  test "perform/1 succeeds for empty project (no sessions)" do
    project = create_project("co-change-empty")

    assert :ok = ComputeCoChange.perform(%Oban.Job{args: %{"project_id" => project.id}})

    assert [] =
             CoChangeGroup
             |> Ash.Query.filter(project_id == ^project.id)
             |> Ash.read!()
  end
end
