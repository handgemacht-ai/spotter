defmodule SpotterWeb.PaneListPromptPatternsTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Project, Session}

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "pp-test", pattern: "^pp-test"})

    Ash.create!(Session, %{
      session_id: Ash.UUID.generate(),
      transcript_dir: "/tmp/pp-test",
      project_id: project.id
    })

    %{project: project}
  end

  describe "prompt patterns disabled" do
    test "prompt-pattern section is not rendered on /" do
      {:ok, _view, html} = live(build_conn(), "/")

      refute html =~ "Repetitive Prompt Patterns"
      refute html =~ ~s(data-testid="prompt-patterns-section")
      refute html =~ ~s(data-testid="analyze-patterns-btn")
      refute html =~ "Analyze patterns"
    end

    test "prompt-pattern URL params are ignored" do
      {:ok, _view, html} =
        live(build_conn(), "/?prompt_patterns_project_id=all&prompt_patterns_timespan=30")

      refute html =~ "Repetitive Prompt Patterns"
      refute html =~ ~s(data-testid="prompt-patterns-section")
    end
  end
end
