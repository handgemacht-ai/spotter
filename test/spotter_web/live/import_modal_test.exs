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

    @tag :import_bug
    test "handle_info destructures TranscriptListing map into entries and pagination" do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      # This is the exact format TranscriptListing.list() returns.
      # The handle_info MUST extract .entries for @import_transcripts
      # and pagination metadata for @import_pagination.
      listing_result = %{
        entries: [
          %{
            session_id: "test-listing-format",
            project_name: "listing-project",
            project_dir: "/tmp/listing-project",
            file_path: "/tmp/listing-project/test-listing-format.jsonl",
            message_count: 7,
            is_team_session: false,
            last_modified: ~U[2026-02-20 10:00:00Z],
            file_size: 512,
            custom_title: "Listing format test",
            summary: "Testing the map format",
            first_prompt: "hello",
            already_imported: false
          }
        ],
        total_count: 1,
        page: 1,
        per_page: 20
      }

      send(view.pid, {:update_import_transcripts, listing_result})

      # Force the process to flush its mailbox by doing a synchronous call
      _ = :sys.get_state(view.pid)

      # Now render — if handle_info didn't extract entries, the template
      # will iterate map keys as tuples and crash on t.project_name
      html = render(view)

      # The entries must render as transcript rows
      assert html =~ ~s(data-testid="transcript-row"),
             "Expected transcript rows. handle_info must extract entries from the map"

      assert html =~ "listing-project"
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

    test "pagination is hidden when results fit on one page" do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      # Only 5 results with per_page 20 — fits on one page
      send(view.pid, {:update_import_pagination, %{total_count: 5, page: 1, per_page: 20}})
      html = render(view)

      refute html =~ ~s(data-testid="pagination")
    end

    test "changing sort order re-sorts displayed transcripts" do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      # Inject transcripts with different message counts
      transcripts = [
        %{
          session_id: "session-few",
          project_name: "proj-a",
          project_dir: "/tmp/proj-a",
          file_path: "/tmp/proj-a/session-few.jsonl",
          message_count: 5,
          is_team_session: false,
          last_modified: ~U[2026-02-10 12:00:00Z],
          file_size: 256,
          custom_title: "Few messages",
          summary: "Short session",
          first_prompt: "hello",
          already_imported: false
        },
        %{
          session_id: "session-many",
          project_name: "proj-b",
          project_dir: "/tmp/proj-b",
          file_path: "/tmp/proj-b/session-many.jsonl",
          message_count: 200,
          is_team_session: false,
          last_modified: ~U[2026-02-01 12:00:00Z],
          file_size: 4096,
          custom_title: "Many messages",
          summary: "Long session",
          first_prompt: "hello",
          already_imported: false
        }
      ]

      send(view.pid, {:update_import_transcripts, transcripts})
      render(view)

      # Change sort to message_count
      html =
        view
        |> element(~s(select[data-testid="sort-select"]))
        |> render_change(%{"sort_by" => "message_count"})

      # After sorting by message count, "200" should appear before "5"
      pos_200 = :binary.match(html, "200") |> elem(0)
      pos_5 = :binary.match(html, ">5<") |> elem(0)
      assert pos_200 < pos_5
    end
  end

  describe "selection and select-all" do
    setup do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      transcripts = [
        %{
          session_id: "sel-session-1",
          project_name: "sel-proj",
          project_dir: "/tmp/sel-proj",
          file_path: "/tmp/sel-proj/sel-session-1.jsonl",
          message_count: 10,
          is_team_session: false,
          last_modified: ~U[2026-02-01 12:00:00Z],
          file_size: 512,
          custom_title: "Selectable session",
          summary: "Test selection",
          first_prompt: "hello",
          already_imported: false
        },
        %{
          session_id: "sel-session-2",
          project_name: "sel-proj",
          project_dir: "/tmp/sel-proj",
          file_path: "/tmp/sel-proj/sel-session-2.jsonl",
          message_count: 20,
          is_team_session: false,
          last_modified: ~U[2026-02-02 12:00:00Z],
          file_size: 1024,
          custom_title: "Another session",
          summary: "More testing",
          first_prompt: "hi",
          already_imported: false
        }
      ]

      send(view.pid, {:update_import_transcripts, transcripts})
      render(view)

      %{view: view}
    end

    test "clicking a row checkbox toggles selection", %{view: view} do
      # Click first transcript's checkbox
      html =
        view
        |> element(
          ~s([data-testid="select-transcript"][value="/tmp/sel-proj/sel-session-1.jsonl"])
        )
        |> render_click()

      # Footer should show selection count
      assert html =~ ~s(data-testid="selection-count")
      assert html =~ "1 selected"
    end

    test "select-all selects all non-imported transcripts", %{view: view} do
      # Add an already-imported transcript to the mix
      transcripts = [
        %{
          session_id: "sel-session-1",
          project_name: "sel-proj",
          project_dir: "/tmp/sel-proj",
          file_path: "/tmp/sel-proj/sel-session-1.jsonl",
          message_count: 10,
          is_team_session: false,
          last_modified: ~U[2026-02-01 12:00:00Z],
          file_size: 512,
          custom_title: "Selectable",
          summary: "Test",
          first_prompt: "hello",
          already_imported: false
        },
        %{
          session_id: "sel-session-2",
          project_name: "sel-proj",
          project_dir: "/tmp/sel-proj",
          file_path: "/tmp/sel-proj/sel-session-2.jsonl",
          message_count: 20,
          is_team_session: false,
          last_modified: ~U[2026-02-02 12:00:00Z],
          file_size: 1024,
          custom_title: "Also selectable",
          summary: "More",
          first_prompt: "hi",
          already_imported: false
        },
        %{
          session_id: "sel-imported",
          project_name: "sel-proj",
          project_dir: "/tmp/sel-proj",
          file_path: "/tmp/sel-proj/sel-imported.jsonl",
          message_count: 5,
          is_team_session: false,
          last_modified: ~U[2026-01-15 12:00:00Z],
          file_size: 256,
          custom_title: "Already imported",
          summary: "Old",
          first_prompt: "hey",
          already_imported: true
        }
      ]

      send(view.pid, {:update_import_transcripts, transcripts})
      render(view)

      # Click select-all
      html =
        view
        |> element(~s([data-testid="select-all"]))
        |> render_click()

      # Should select only the 2 non-imported transcripts
      assert html =~ "2 selected"
    end

    test "import button is disabled when 0 selected and enabled with count when selected", %{
      view: view
    } do
      html = render(view)

      # With no selection, import action button should be disabled
      assert has_element?(view, ~s([data-testid="import-action-button"][disabled]))

      # Select a transcript
      view
      |> element(~s([data-testid="select-transcript"][value="/tmp/sel-proj/sel-session-1.jsonl"]))
      |> render_click()

      html = render(view)

      # Button should now be enabled with count and primary styling
      refute has_element?(view, ~s([data-testid="import-action-button"][disabled]))
      assert html =~ "Import 1"
      assert has_element?(view, ~s([data-testid="import-action-button"].btn-primary))
    end

    test "select-all checkbox reflects selection state", %{view: view} do
      # Select all first
      view
      |> element(~s([data-testid="select-all"]))
      |> render_click()

      # Both should be selected and select-all should be checked
      html = render(view)
      assert html =~ "2 selected"
      assert has_element?(view, ~s([data-testid="select-all"][checked]))

      # Deselect one row
      view
      |> element(~s([data-testid="select-transcript"][value="/tmp/sel-proj/sel-session-1.jsonl"]))
      |> render_click()

      html = render(view)

      # Count should drop to 1
      assert html =~ "1 selected"
      # Select-all checkbox should no longer be checked
      refute has_element?(view, ~s([data-testid="select-all"][checked]))
    end
  end

  describe "import action" do
    setup do
      {:ok, view, _html} = live(build_conn(), "/")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      transcripts = [
        %{
          session_id: "import-session-1",
          project_name: "import-proj",
          project_dir: "/tmp/import-proj",
          file_path: "/tmp/import-proj/import-session-1.jsonl",
          message_count: 15,
          is_team_session: false,
          last_modified: ~U[2026-02-10 12:00:00Z],
          file_size: 512,
          custom_title: "Import test session",
          summary: "Testing import",
          first_prompt: "hello",
          already_imported: false
        }
      ]

      send(view.pid, {:update_import_transcripts, transcripts})
      render(view)

      # Select the transcript
      view
      |> element(
        ~s([data-testid="select-transcript"][value="/tmp/import-proj/import-session-1.jsonl"])
      )
      |> render_click()

      %{view: view}
    end

    test "clicking import button shows importing progress", %{view: view} do
      html =
        view
        |> element(~s([data-testid="import-action-button"]))
        |> render_click()

      assert html =~ ~s(data-testid="import-progress")
      assert html =~ "Importing"
    end

    test "successful import closes modal and shows success flash", %{view: view} do
      # Trigger import
      view
      |> element(~s([data-testid="import-action-button"]))
      |> render_click()

      # Simulate successful import completion
      send(view.pid, {:import_complete, %{success_count: 1, error_count: 0, errors: []}})
      html = render(view)

      # Modal should be closed
      refute html =~ ~s(data-testid="import-modal")

      # Success flash
      assert html =~ "Successfully imported 1 transcript"
    end

    test "partial failure keeps modal open and shows error details", %{view: view} do
      view
      |> element(~s([data-testid="import-action-button"]))
      |> render_click()

      # Simulate partial failure
      send(
        view.pid,
        {:import_complete,
         %{
           success_count: 0,
           error_count: 1,
           errors: [
             %{
               file_path: "/tmp/import-proj/import-session-1.jsonl",
               reason: "Invalid JSONL format"
             }
           ]
         }}
      )

      html = render(view)

      # Modal should stay open
      assert html =~ ~s(data-testid="import-modal")

      # Error details shown
      assert html =~ "Invalid JSONL format"
    end

    test "after successful import, re-opening modal marks transcripts as already-imported", %{
      view: view
    } do
      # Trigger import
      view
      |> element(~s([data-testid="import-action-button"]))
      |> render_click()

      # Complete successfully
      send(view.pid, {:import_complete, %{success_count: 1, error_count: 0, errors: []}})
      render(view)

      # Re-open modal
      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      # Push the same transcript back but now marked as already-imported
      transcripts = [
        %{
          session_id: "import-session-1",
          project_name: "import-proj",
          project_dir: "/tmp/import-proj",
          file_path: "/tmp/import-proj/import-session-1.jsonl",
          message_count: 15,
          is_team_session: false,
          last_modified: ~U[2026-02-10 12:00:00Z],
          file_size: 512,
          custom_title: "Import test session",
          summary: "Testing import",
          first_prompt: "hello",
          already_imported: true
        }
      ]

      send(view.pid, {:update_import_transcripts, transcripts})
      html = render(view)

      # The transcript should now show as already-imported
      assert html =~ "already-imported"
      assert has_element?(view, ~s([data-testid="select-transcript"][disabled]))
      # Import button should be disabled (nothing selectable)
      assert has_element?(view, ~s([data-testid="import-action-button"][disabled]))
    end

    test "import emits telemetry spans with correct attributes", %{view: view} do
      # Set up OTel span capture
      :otel_simple_processor.set_exporter(:otel_exporter_pid, self())

      # Trigger import
      view
      |> element(~s([data-testid="import-action-button"]))
      |> render_click()

      # Complete successfully
      send(view.pid, {:import_complete, %{success_count: 1, error_count: 0, errors: []}})
      render(view)

      # Collect spans
      Process.sleep(100)
      spans = collect_spans([])

      span_names = Enum.map(spans, &to_string(elem(&1, 6)))

      assert "spotter.import_modal.import" in span_names,
             "Expected import span, got: #{inspect(span_names)}"

      assert "spotter.import_modal.import_complete" in span_names,
             "Expected import_complete span, got: #{inspect(span_names)}"
    end
  end

  defp collect_spans(acc) do
    receive do
      {:span, span} -> collect_spans([span | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
