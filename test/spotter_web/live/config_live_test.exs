defmodule SpotterWeb.ConfigLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Config.Setting
  alias Spotter.Repo
  alias Spotter.Transcripts.Project

  require Ash.Query

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  describe "page rendering" do
    test "renders all four section headings" do
      {:ok, _view, html} = live(build_conn(), "/settings/config")

      assert html =~ "Transcripts"
      assert html =~ "LLM"
      assert html =~ "OpenTelemetry"
      assert html =~ "Server"
    end

    test "shows DB override when setting exists" do
      Ash.create!(Setting, %{key: "summary_model", value: "custom-model"})

      {:ok, _view, html} = live(build_conn(), "/settings/config")

      assert html =~ "custom-model"
      assert html =~ "DB override"
    end

    test "shows projects from DB when they exist" do
      Ash.create!(Project, %{name: "my-proj", pattern: "^my-proj"})

      {:ok, _view, html} = live(build_conn(), "/settings/config")

      assert html =~ "my-proj"
    end

    test "shows empty state when no projects exist" do
      {:ok, _view, html} = live(build_conn(), "/settings/config")

      assert html =~ "No projects configured"
    end

    test "shows API key status" do
      {:ok, _view, html} = live(build_conn(), "/settings/config")

      # Should show either Yes or No
      assert html =~ "Anthropic API key configured?"
    end

    test "shows read-only OpenTelemetry values" do
      {:ok, _view, html} = live(build_conn(), "/settings/config")

      assert html =~ "SPOTTER_OTEL_ENABLED"
      assert html =~ "OTEL_EXPORTER"
    end

    test "shows server port" do
      {:ok, _view, html} = live(build_conn(), "/settings/config")

      assert html =~ "Port"
    end
  end

  describe "prompt_patterns_sessions_per_run" do
    test "form renders with default value" do
      {:ok, _view, html} = live(build_conn(), "/settings/config")

      assert html =~ "prompt_patterns_sessions_per_run"
    end

    test "invalid value keeps prior value" do
      {:ok, view, _html} = live(build_conn(), "/settings/config")

      view
      |> element(~s(form[phx-submit="save_prompt_patterns_sessions_per_run"]))
      |> render_submit(%{"value" => "not-a-number"})

      html = render(view)
      # Default value should still be shown
      assert html =~ "10"
    end
  end

  describe "validation (client-side)" do
    test "invalid budget does not change the displayed value" do
      {:ok, view, _html} = live(build_conn(), "/settings/config")

      html =
        view
        |> element(~s(form[phx-submit="save_summary_budget"]))
        |> render_submit(%{"value" => "not-a-number"})

      # The re-rendered page should still show the default budget
      assert html =~ "4000"
    end

    test "invalid regex pattern does not create project" do
      {:ok, view, _html} = live(build_conn(), "/settings/config")

      html =
        view
        |> element(~s(form[phx-submit="project_create"]))
        |> render_submit(%{"name" => "bad-proj", "pattern" => "[invalid"})

      # The bad project should not appear
      refute html =~ "bad-proj"
    end
  end

  describe "project_delete" do
    test "deletes an existing project without crash" do
      project = Ash.create!(Project, %{name: "del-proj", pattern: "^del"})
      {:ok, view, html} = live(build_conn(), "/settings/config")
      assert html =~ "del-proj"

      view
      |> element(~s(button[phx-click="project_confirm_delete"][phx-value-id="#{project.id}"]))
      |> render_click()

      html =
        view
        |> element(~s(button[phx-click="project_delete"][phx-value-id="#{project.id}"]))
        |> render_click()

      # Project is removed and page shows empty state
      refute html =~ "del-proj"
      assert html =~ "No projects configured"
    end

    test "repeated delete of same id does not crash" do
      project = Ash.create!(Project, %{name: "dup-del", pattern: "^dup"})
      {:ok, view, _html} = live(build_conn(), "/settings/config")

      # First delete
      view
      |> element(~s(button[phx-click="project_confirm_delete"][phx-value-id="#{project.id}"]))
      |> render_click()

      view
      |> element(~s(button[phx-click="project_delete"][phx-value-id="#{project.id}"]))
      |> render_click()

      # Second delete with same id (project already gone) - should not crash
      html = render_click(view, "project_delete", %{"id" => project.id})
      # View still renders without crashing
      assert html =~ "No projects configured"
    end
  end
end
