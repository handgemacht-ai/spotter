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

    test "renders transcript rows with project name, message count, and last updated" do
      {:ok, view, _html} = live(build_conn(), "/")

      # Open modal then push transcript data into assigns
      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      transcripts = [
        %{
          session_id: "test-session-abc",
          project_name: "my-cool-project",
          project_dir: "/tmp/my-cool-project",
          file_path: "/tmp/my-cool-project/test-session-abc.jsonl",
          message_count: 42,
          is_team_session: false,
          last_modified: ~U[2026-02-01 12:00:00Z],
          file_size: 1024,
          custom_title: "Fix authentication bug",
          summary: "Fixed the login flow",
          first_prompt: "Help me fix the auth bug",
          already_imported: false
        }
      ]

      send(view.pid, {:update_import_transcripts, transcripts})
      html = render(view)

      assert html =~ ~s(data-testid="transcript-row")
      assert html =~ "my-cool-project"
      assert html =~ "42"
    end

    test "already-imported rows have distinct styling and disabled checkbox" do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      transcripts = [
        %{
          session_id: "imported-session",
          project_name: "old-project",
          project_dir: "/tmp/old-project",
          file_path: "/tmp/old-project/imported-session.jsonl",
          message_count: 10,
          is_team_session: false,
          last_modified: ~U[2026-01-15 08:00:00Z],
          file_size: 512,
          custom_title: "Old session",
          summary: "Already synced",
          first_prompt: "hello",
          already_imported: true
        }
      ]

      send(view.pid, {:update_import_transcripts, transcripts})
      html = render(view)

      assert html =~ "already-imported"
      assert html =~ "disabled"
    end

    test "team session rows show team indicator" do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      transcripts = [
        %{
          session_id: "team-session-xyz",
          project_name: "team-project",
          project_dir: "/tmp/team-project",
          file_path: "/tmp/team-project/team-session-xyz.jsonl",
          message_count: 100,
          is_team_session: true,
          last_modified: ~U[2026-02-20 16:00:00Z],
          file_size: 4096,
          custom_title: "Team planning session",
          summary: "Planning sprint",
          first_prompt: "Let's plan the sprint",
          already_imported: false
        }
      ]

      send(view.pid, {:update_import_transcripts, transcripts})
      html = render(view)

      # Team sessions should have a visual indicator (● dot badge)
      assert html =~ ~s(data-testid="transcript-row")
      assert html =~ "●"
    end
  end
end
