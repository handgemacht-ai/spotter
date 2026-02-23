defmodule Spotter.Services.TranscriptListingTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.TranscriptListing

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    # Route OTel spans to this test process for telemetry assertions
    :otel_simple_processor.set_exporter(:otel_exporter_pid, self())

    tmp_dir =
      Path.join(System.tmp_dir!(), "listing_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  describe "list/1 pagination" do
    test "returns first page with defaults (page 1, per_page 20)", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "pagination-project")
      File.mkdir_p!(project_dir)

      # Create 25 transcript files
      for i <- 1..25 do
        id = Ash.UUID.generate()
        write_jsonl_file(project_dir, id)
        write_sessions_index_entry(project_dir, id, "Session #{i}")
      end

      result = TranscriptListing.list(transcript_roots: [tmp_dir])

      assert %{entries: entries, total_count: 25, page: 1, per_page: 20} = result
      assert length(entries) == 20
    end

    test "returns second page with remaining entries", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "page2-project")
      File.mkdir_p!(project_dir)

      for i <- 1..25 do
        id = Ash.UUID.generate()
        write_jsonl_file(project_dir, id)
        write_sessions_index_entry(project_dir, id, "Session #{i}")
      end

      result = TranscriptListing.list(transcript_roots: [tmp_dir], page: 2)

      assert %{entries: entries, total_count: 25, page: 2, per_page: 20} = result
      assert length(entries) == 5
    end

    test "returns empty entries for page beyond last", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "beyond-project")
      File.mkdir_p!(project_dir)

      id = Ash.UUID.generate()
      write_jsonl_file(project_dir, id)
      write_sessions_index_entry(project_dir, id, "Only one")

      result = TranscriptListing.list(transcript_roots: [tmp_dir], page: 99)

      assert %{entries: [], total_count: 1, page: 99} = result
    end

    test "returns empty result when no transcripts exist", %{tmp_dir: tmp_dir} do
      result = TranscriptListing.list(transcript_roots: [tmp_dir])

      assert %{entries: [], total_count: 0, page: 1, per_page: 20} = result

      # TELEMETRY: listing span emitted even for empty results
      spans = collect_spans()
      span_names = Enum.map(spans, &to_string(elem(&1, 6)))
      assert "spotter.transcript_listing.list" in span_names
    end
  end

  describe "list/1 sorting" do
    test "sorts by last_modified descending by default", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "sort-project")
      File.mkdir_p!(project_dir)

      older_id = Ash.UUID.generate()
      newer_id = Ash.UUID.generate()

      older_path = write_jsonl_file(project_dir, older_id)
      newer_path = write_jsonl_file(project_dir, newer_id)

      # Set file mtimes to control sort order
      File.touch!(older_path, {{2026, 1, 1}, {0, 0, 0}})
      File.touch!(newer_path, {{2026, 2, 1}, {0, 0, 0}})

      write_sessions_index_multi(project_dir, [
        {older_id, "Older", "2026-01-01T00:00:00Z"},
        {newer_id, "Newer", "2026-02-01T00:00:00Z"}
      ])

      result = TranscriptListing.list(transcript_roots: [tmp_dir])

      [first, second] = result.entries
      assert DateTime.compare(first.last_modified, second.last_modified) == :gt
    end

    test "sorts by project_name ascending", %{tmp_dir: tmp_dir} do
      for name <- ["zulu-proj", "alpha-proj"] do
        dir = Path.join(tmp_dir, name)
        File.mkdir_p!(dir)
        id = Ash.UUID.generate()
        write_jsonl_file(dir, id)
        write_sessions_index_entry(dir, id, "Session in #{name}")
      end

      result =
        TranscriptListing.list(
          transcript_roots: [tmp_dir],
          sort_by: :project_name,
          sort_dir: :asc
        )

      names = Enum.map(result.entries, & &1.project_name)
      assert names == ["alpha-proj", "zulu-proj"]
    end
  end

  describe "list/1 filtering" do
    test "project_filter returns only matching project", %{tmp_dir: tmp_dir} do
      for name <- ["alpha", "beta"] do
        dir = Path.join(tmp_dir, name)
        File.mkdir_p!(dir)
        id = Ash.UUID.generate()
        write_jsonl_file(dir, id)
        write_sessions_index_entry(dir, id, "Session in #{name}")
      end

      result = TranscriptListing.list(transcript_roots: [tmp_dir], project_filter: "alpha")

      assert result.total_count == 1
      assert hd(result.entries).project_name == "alpha"
    end

    test "search matches across custom_title, first_prompt, project_name", %{tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "search-proj")
      File.mkdir_p!(dir)

      id = Ash.UUID.generate()
      write_jsonl_file(dir, id)
      write_sessions_index_entry(dir, id, "Refactor authentication")

      result = TranscriptListing.list(transcript_roots: [tmp_dir], search: "refactor")

      assert result.total_count == 1
      assert hd(result.entries).custom_title == "Refactor authentication"
    end

    test "search is case-insensitive", %{tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "case-proj")
      File.mkdir_p!(dir)

      id = Ash.UUID.generate()
      write_jsonl_file(dir, id)
      write_sessions_index_entry(dir, id, "Fix Database Migration")

      result = TranscriptListing.list(transcript_roots: [tmp_dir], search: "DATABASE")

      assert result.total_count == 1
    end

    test "search with no matches returns empty", %{tmp_dir: tmp_dir} do
      dir = Path.join(tmp_dir, "nomatch-proj")
      File.mkdir_p!(dir)

      id = Ash.UUID.generate()
      write_jsonl_file(dir, id)
      write_sessions_index_entry(dir, id, "Something else")

      result = TranscriptListing.list(transcript_roots: [tmp_dir], search: "zzzznotfound")

      assert result.total_count == 0
      assert result.entries == []
    end
  end

  describe "list_project_names/0" do
    test "returns sorted project names", %{tmp_dir: tmp_dir} do
      for name <- ["zeta", "alpha"] do
        dir = Path.join(tmp_dir, name)
        File.mkdir_p!(dir)
        id = Ash.UUID.generate()
        write_jsonl_file(dir, id)
        write_sessions_index_entry(dir, id, "Session")
      end

      assert {:ok, names} = TranscriptListing.list_project_names(transcript_roots: [tmp_dir])
      assert names == ["alpha", "zeta"]
    end
  end

  # --- Fixture helpers ---

  defp write_jsonl_file(dir, session_id) do
    lines = [
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
        "content" => [%{"type" => "text", "text" => "hello"}],
        "timestamp" => "2026-02-01T12:00:01Z"
      }
    ]

    path = Path.join(dir, "#{session_id}.jsonl")
    File.write!(path, Enum.map_join(lines, "\n", &Jason.encode!/1))
    path
  end

  defp write_sessions_index_entry(dir, session_id, title) do
    # Read existing index or start fresh
    index_path = Path.join(dir, "sessions-index.json")

    existing_entries =
      case File.read(index_path) do
        {:ok, content} -> Jason.decode!(content)["entries"] || []
        {:error, _} -> []
      end

    entry = %{
      "sessionId" => session_id,
      "customTitle" => title,
      "summary" => "Summary for #{title}",
      "firstPrompt" => "hello",
      "created" => "2026-01-01T00:00:00Z",
      "modified" => "2026-02-01T00:00:00Z"
    }

    index = %{"entries" => existing_entries ++ [entry]}
    File.write!(index_path, Jason.encode!(index))
  end

  defp write_sessions_index_multi(dir, entries) do
    index = %{
      "entries" =>
        Enum.map(entries, fn {session_id, title, modified} ->
          %{
            "sessionId" => session_id,
            "customTitle" => title,
            "summary" => "Auto-generated",
            "firstPrompt" => "hello",
            "created" => "2026-01-01T00:00:00Z",
            "modified" => modified
          }
        end)
    }

    path = Path.join(dir, "sessions-index.json")
    File.write!(path, Jason.encode!(index))
    path
  end

  defp collect_spans do
    Process.sleep(100)
    collect_spans([])
  end

  defp collect_spans(acc) do
    receive do
      {:span, span} -> collect_spans([span | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
