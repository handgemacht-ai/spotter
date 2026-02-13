defmodule Spotter.Transcripts.ProjectTimezoneValidationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.Project

  setup do
    Sandbox.checkout(Repo)
  end

  describe "timezone validation" do
    test "creates project with default timezone Etc/UTC" do
      project = Ash.create!(Project, %{name: "tz-default", pattern: "^tz"})
      assert project.timezone == "Etc/UTC"
    end

    test "creates project with valid timezone" do
      project =
        Ash.create!(Project, %{name: "tz-la", pattern: "^tz-la", timezone: "America/Los_Angeles"})

      assert project.timezone == "America/Los_Angeles"
    end

    test "updates project with valid timezone" do
      project = Ash.create!(Project, %{name: "tz-update", pattern: "^tz-update"})
      updated = Ash.update!(project, %{timezone: "Europe/Vienna"})
      assert updated.timezone == "Europe/Vienna"
    end

    test "rejects invalid timezone on create" do
      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(Project, %{
                 name: "tz-bad",
                 pattern: "^tz-bad",
                 timezone: "Not/A_Timezone"
               })
    end

    test "rejects invalid timezone on update" do
      project = Ash.create!(Project, %{name: "tz-bad-upd", pattern: "^tz-bad-upd"})

      assert {:error, %Ash.Error.Invalid{}} =
               Ash.update(project, %{timezone: "Not/A_Timezone"})
    end

    test "rejects empty string timezone" do
      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(Project, %{name: "tz-empty", pattern: "^tz-empty", timezone: ""})
    end

    test "rejects whitespace-only timezone" do
      assert {:error, %Ash.Error.Invalid{}} =
               Ash.create(Project, %{name: "tz-ws", pattern: "^tz-ws", timezone: "   "})
    end
  end
end
