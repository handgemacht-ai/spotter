defmodule SpotterWeb.PaneListLiveTimezoneTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.Project

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    project = Ash.create!(Project, %{name: "tz-live-test", pattern: "^tz-live"})
    %{project: project}
  end

  describe "timezone editor" do
    test "renders timezone input with default value", %{project: _project} do
      {:ok, _view, html} = live(build_conn(), "/")
      assert html =~ "Etc/UTC"
      assert html =~ "Save TZ"
    end

    test "updates timezone with valid value", %{project: project} do
      {:ok, view, _html} = live(build_conn(), "/")

      html =
        view
        |> element("form[phx-submit=update_timezone]")
        |> render_submit(%{"project_id" => project.id, "timezone" => "America/New_York"})

      refute html =~ "invalid"

      reloaded = Ash.get!(Project, project.id)
      assert reloaded.timezone == "America/New_York"
    end

    test "shows error for invalid timezone", %{project: project} do
      {:ok, view, _html} = live(build_conn(), "/")

      html =
        view
        |> element("form[phx-submit=update_timezone]")
        |> render_submit(%{"project_id" => project.id, "timezone" => "Not/Real"})

      assert html =~ "invalid IANA timezone"
    end
  end
end
