defmodule SpotterWeb.ImportModalTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    :ok
  end

  describe "Import button on dashboard" do
    test "dashboard renders an Import button" do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-testid="import-button")
      assert html =~ "Import"
    end
  end

  describe "modal open/close" do
    test "clicking Import button opens the import modal with title" do
      {:ok, view, _html} = live(build_conn(), "/")

      html =
        view
        |> element(~s([data-testid="import-button"]))
        |> render_click()

      assert html =~ ~s(data-testid="import-modal")
      assert html =~ "Import Transcripts"
    end

    test "close button dismisses the modal" do
      {:ok, view, _html} = live(build_conn(), "/")

      # Open modal
      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      # Close via close button
      html =
        view
        |> element(~s([data-testid="import-modal-close"]))
        |> render_click()

      refute html =~ ~s(data-testid="import-modal")
    end

    test "pressing Escape closes the modal" do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      html = render_keydown(view, "close_import_modal", %{"key" => "Escape"})

      refute html =~ ~s(data-testid="import-modal")
    end

    test "clicking backdrop closes the modal" do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      # phx-click-away triggers close_import_modal
      html = render_click(view, "close_import_modal", %{})

      refute html =~ ~s(data-testid="import-modal")
    end
  end

  describe "transcript table in modal" do
    test "shows empty state when no transcripts found" do
      {:ok, view, _html} = live(build_conn(), "/")

      html =
        view
        |> element(~s([data-testid="import-button"]))
        |> render_click()

      assert html =~ "No transcripts found"
      refute html =~ ~s(data-testid="transcript-row")
    end
  end
end
