defmodule SpotterWeb.ImportModalMapFormatTest do
  @moduledoc """
  Regression test for the Import modal crash when TranscriptListing.list()
  returns a pagination map instead of a plain list.

  Bug: handle_info({:update_import_transcripts, transcripts}, socket) assigned
  the raw %{entries: [...], total_count: N, page: 1, per_page: 20} map to
  @import_transcripts. The template iterated it with `for t <- @import_transcripts`
  which yielded {key, value} tuples instead of transcript maps, crashing on
  t.project_name.
  """
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Config.Setting

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "handle_info with TranscriptListing map format" do
    test "assigns entries list (not raw map) to import_transcripts" do
      {:ok, view, _html} = live(build_conn(), "/sessions")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      # This is the exact format TranscriptListing.list() returns
      listing_result = %{
        entries: [
          %{
            session_id: "map-format-test",
            project_name: "map-format-project",
            project_dir: "/tmp/map-format-project",
            file_path: "/tmp/map-format-project/map-format-test.jsonl",
            message_count: 7,
            is_team_session: false,
            last_modified: ~U[2026-02-20 10:00:00Z],
            file_size: 512,
            custom_title: "Map format test",
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

      # Force mailbox flush via synchronous call
      %{socket: socket} = :sys.get_state(view.pid)
      import_transcripts = socket.assigns.import_transcripts

      # import_transcripts MUST be a list (the entries), not the raw map
      assert is_list(import_transcripts),
             "import_transcripts should be a list, got: #{inspect(import_transcripts, limit: 3)}"

      assert length(import_transcripts) == 1
      assert hd(import_transcripts).project_name == "map-format-project"
    end

    test "extracts pagination metadata into import_pagination assign" do
      {:ok, view, _html} = live(build_conn(), "/sessions")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      listing_result = %{
        entries: [],
        total_count: 45,
        page: 2,
        per_page: 20
      }

      send(view.pid, {:update_import_transcripts, listing_result})
      %{socket: socket} = :sys.get_state(view.pid)

      pagination = socket.assigns.import_pagination

      assert pagination.total_count == 45
      assert pagination.page == 2
      assert pagination.per_page == 20
    end

    test "renders entries as transcript rows after receiving map format" do
      {:ok, view, _html} = live(build_conn(), "/sessions")

      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      listing_result = %{
        entries: [
          %{
            session_id: "render-test",
            project_name: "render-project",
            project_dir: "/tmp/render-project",
            file_path: "/tmp/render-project/render-test.jsonl",
            message_count: 42,
            is_team_session: true,
            last_modified: ~U[2026-02-15 08:00:00Z],
            file_size: 1024,
            custom_title: "Render test",
            summary: "Testing render",
            first_prompt: "hello render",
            already_imported: false
          }
        ],
        total_count: 1,
        page: 1,
        per_page: 20
      }

      send(view.pid, {:update_import_transcripts, listing_result})
      html = render(view)

      # Modal stays open and transcript rows render correctly
      assert html =~ ~s(data-testid="import-modal")
      assert html =~ ~s(data-testid="transcript-row")
      assert html =~ "render-project"
      assert html =~ "42"
    end
  end

  describe "full integration: open_import_modal → TranscriptListing.list() → render" do
    setup do
      # Create a temp dir with real transcript files
      tmp_dir =
        Path.join(System.tmp_dir!(), "import_integration_#{System.unique_integer([:positive])}")

      project_dir = Path.join(tmp_dir, "integration-project")
      File.mkdir_p!(project_dir)

      session_id = Ash.UUID.generate()

      # Write a JSONL transcript file
      jsonl_lines = [
        %{
          "type" => "system",
          "sessionId" => session_id,
          "cwd" => "/home/user/project",
          "version" => "1.0"
        },
        %{
          "type" => "human",
          "role" => "user",
          "sessionId" => session_id,
          "content" => [%{"type" => "text", "text" => "fix the auth bug"}],
          "timestamp" => "2026-02-20T12:00:01Z"
        }
      ]

      jsonl_path = Path.join(project_dir, "#{session_id}.jsonl")
      File.write!(jsonl_path, Enum.map_join(jsonl_lines, "\n", &Jason.encode!/1))

      # Write a sessions-index.json so discovery finds the transcript
      index = %{
        "entries" => [
          %{
            "sessionId" => session_id,
            "customTitle" => "Auth bug fix",
            "summary" => "Fixed the login flow",
            "firstPrompt" => "fix the auth bug",
            "created" => "2026-02-20T12:00:00Z",
            "modified" => "2026-02-20T12:30:00Z"
          }
        ]
      }

      File.write!(Path.join(project_dir, "sessions-index.json"), Jason.encode!(index))

      # Point transcript_roots to our temp dir via DB setting
      Ash.create!(Setting, %{key: "transcript_roots", value: Jason.encode!([tmp_dir])})

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      %{tmp_dir: tmp_dir, session_id: session_id}
    end

    test "clicking Import loads real transcripts through TranscriptListing.list() pipeline" do
      {:ok, view, _html} = live(build_conn(), "/sessions")

      # Click Import — this triggers the real path:
      # open_import_modal → Task.start → TranscriptListing.list() → handle_info
      view
      |> element(~s([data-testid="import-button"]))
      |> render_click()

      # The async Task needs time to discover files and send the message back
      # Poll until transcript rows appear or timeout
      html =
        Enum.reduce_while(1..20, render(view), fn _i, _acc ->
          Process.sleep(100)
          html = render(view)

          if html =~ ~s(data-testid="transcript-row") do
            {:halt, html}
          else
            {:cont, html}
          end
        end)

      # The modal must be open with real transcript data
      assert html =~ ~s(data-testid="import-modal"),
             "Modal should be open"

      assert html =~ ~s(data-testid="transcript-row"),
             "Expected transcript rows from real TranscriptListing.list() pipeline"

      assert html =~ "integration-project",
             "Expected project name from discovered transcript"

      # Verify the assigns are a list, not the raw map
      %{socket: socket} = :sys.get_state(view.pid)

      assert is_list(socket.assigns.import_transcripts),
             "import_transcripts should be a list after real pipeline, got: #{inspect(socket.assigns.import_transcripts, limit: 3)}"

      # Pagination should have been populated from the map
      assert is_map(socket.assigns.import_pagination)
      assert Map.has_key?(socket.assigns.import_pagination, :total_count)
    end
  end
end
