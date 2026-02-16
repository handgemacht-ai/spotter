defmodule SpotterWeb.PaneListPromptPatternsTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Project, PromptPattern, PromptPatternRun, Session}

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

  describe "prompt patterns section" do
    test "section renders on /" do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "Repetitive Prompt Patterns"
      assert html =~ ~s(data-testid="prompt-patterns-section")
      assert html =~ ~s(data-testid="analyze-patterns-btn")
    end

    test "defaults to the only project when no prompt-pattern project param is provided", ctx do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(phx-value-id="#{ctx.project.id}" class="filter-btn is-active")
    end

    test "shows empty state with remaining session count when no runs exist" do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "No prompt pattern analysis yet"
      assert html =~ ~s(data-testid="pp-remaining-count")
      assert html =~ "more completed"
      assert html =~ "Analyze patterns"
    end

    test "shows ready-to-start message when threshold is met", ctx do
      Ash.create!(Spotter.Config.Setting, %{
        key: "prompt_patterns_sessions_per_run",
        value: "1"
      })

      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        project_id: ctx.project.id,
        hook_ended_at: DateTime.utc_now()
      })

      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ "ready to start"
    end

    test "clicking Analyze patterns enqueues an Oban job" do
      {:ok, view, _html} = live(build_conn(), "/")

      view |> element(~s([data-testid="analyze-patterns-btn"])) |> render_click()

      assert_enqueued(worker: Spotter.Transcripts.Jobs.ComputePromptPatterns)
    end

    test "shows completed run results" do
      run =
        Ash.create!(PromptPatternRun, %{
          scope: :global,
          timespan_days: 30,
          prompt_limit: 500,
          max_prompt_chars: 400,
          status: :completed
        })

      Ash.create!(PromptPattern, %{
        run_id: run.id,
        needle: "fix the bug",
        label: "Bug fix requests",
        count_total: 5,
        examples: %{"items" => ["fix the bug in login"]},
        confidence: 0.85
      })

      {:ok, _view, html} =
        live(build_conn(), "/?prompt_patterns_project_id=all&prompt_patterns_timespan=30")

      assert html =~ "Bug fix requests"
      assert html =~ "fix the bug"
      assert html =~ "5"
    end

    test "shows error state for failed run" do
      run =
        Ash.create!(PromptPatternRun, %{
          scope: :global,
          timespan_days: 30,
          prompt_limit: 500,
          max_prompt_chars: 400,
          status: :queued
        })

      Ash.update!(run, %{error: "missing_api_key"}, action: :fail)

      {:ok, _view, html} =
        live(build_conn(), "/?prompt_patterns_project_id=all&prompt_patterns_timespan=30")

      assert html =~ "Analysis failed"
      assert html =~ "missing_api_key"
    end

    test "timespan selection updates via push_patch" do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s(.filter-bar button[phx-value-value="7"]))
      |> render_click()

      # After push_patch, the 7d button should be active
      html = render(view)
      assert html =~ ~s(phx-value-value="7" class="filter-btn is-active")
    end
  end

  defp assert_enqueued(opts) do
    worker = Keyword.fetch!(opts, :worker)
    worker_str = inspect(worker)

    import Ecto.Query

    jobs =
      Spotter.Repo.all(
        from(j in Oban.Job,
          where: j.worker == ^worker_str,
          where: j.state == "available"
        )
      )

    assert jobs != [], "Expected #{worker_str} job to be enqueued"
  end
end
