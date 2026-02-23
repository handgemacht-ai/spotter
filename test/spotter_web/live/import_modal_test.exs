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

  describe "filter, sort, and pagination controls" do
    test "modal renders project filter dropdown with All Projects default" do
      {:ok, view, _html} = live(build_conn(), "/")

      html =
        view
        |> element(~s([data-testid="import-button"]))
        |> render_click()

      # Project filter select should be present with default "All Projects"
      assert html =~ ~s(data-testid="project-filter")
      assert html =~ "All Projects"
    end

    test "modal renders sort dropdown with Last Updated, Message Count, and Project Name options" do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      # Sort dropdown must be a <select> element with sort options
      assert has_element?(view, ~s(select[data-testid="sort-select"]))

      assert has_element?(
               view,
               ~s(select[data-testid="sort-select"] option[value="last_modified"])
             )

      assert has_element?(
               view,
               ~s(select[data-testid="sort-select"] option[value="message_count"])
             )

      assert has_element?(
               view,
               ~s(select[data-testid="sort-select"] option[value="project_name"])
             )
    end

    test "selecting a project filter updates displayed transcripts" do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      # Inject transcripts from two projects
      transcripts = [
        %{
          session_id: "session-alpha",
          project_name: "alpha-proj",
          project_dir: "/tmp/alpha-proj",
          file_path: "/tmp/alpha-proj/session-alpha.jsonl",
          message_count: 5,
          is_team_session: false,
          last_modified: ~U[2026-02-01 12:00:00Z],
          file_size: 512,
          custom_title: "Alpha session",
          summary: "Alpha work",
          first_prompt: "hello alpha",
          already_imported: false
        },
        %{
          session_id: "session-beta",
          project_name: "beta-proj",
          project_dir: "/tmp/beta-proj",
          file_path: "/tmp/beta-proj/session-beta.jsonl",
          message_count: 10,
          is_team_session: false,
          last_modified: ~U[2026-02-02 12:00:00Z],
          file_size: 1024,
          custom_title: "Beta session",
          summary: "Beta work",
          first_prompt: "hello beta",
          already_imported: false
        }
      ]

      send(view.pid, {:update_import_transcripts, transcripts})
      render(view)

      # Select "alpha-proj" in the project filter
      html =
        view
        |> element(~s(select[data-testid="project-filter"]))
        |> render_change(%{"project_filter" => "alpha-proj"})

      # Should show only alpha-proj transcripts
      assert html =~ "alpha-proj"
      refute html =~ "beta-proj"
    end

    test "pagination renders when total exceeds per_page" do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      # Inject pagination metadata to simulate multi-page results
      send(view.pid, {:update_import_pagination, %{total_count: 45, page: 1, per_page: 20}})
      html = render(view)

      assert html =~ ~s(data-testid="pagination")
      assert html =~ ~s(data-testid="page-1")
      assert html =~ ~s(data-testid="page-2")
      assert html =~ ~s(data-testid="page-3")
    end

    test "clicking page 2 updates the active page" do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      # Set up pagination state
      send(view.pid, {:update_import_pagination, %{total_count: 45, page: 1, per_page: 20}})
      render(view)

      # Click page 2
      html =
        view
        |> element(~s([data-testid="page-2"]))
        |> render_click()

      # Page 2 button should now be the active/current page
      assert html =~ ~s(data-testid="pagination")
      # The active page button should have an aria-current or active class
      assert has_element?(view, ~s([data-testid="page-2"][aria-current="page"]))
    end
  end
end
