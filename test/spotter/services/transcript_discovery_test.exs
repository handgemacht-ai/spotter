defmodule Spotter.Services.TranscriptDiscoveryTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.TranscriptDiscovery

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    # Route OTel spans to this test process for telemetry assertions
    :otel_simple_processor.set_exporter(:otel_exporter_pid, self())

    tmp_dir =
      Path.join(System.tmp_dir!(), "spotter_discovery_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    %{tmp_dir: tmp_dir}
  end

  describe "discover/1 basic scanning" do
    test "returns transcript previews from a directory with JSONL files and sessions-index.json",
         %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()
      project_dir = Path.join(tmp_dir, "my-project")
      File.mkdir_p!(project_dir)

      write_jsonl_file(project_dir, session_id)
      write_sessions_index(project_dir, session_id)

      results = TranscriptDiscovery.discover(tmp_dir)

      assert is_list(results)
      assert length(results) == 1

      preview = hd(results)
      assert preview.session_id == session_id
      assert preview.project_name == "my-project"
      assert preview.file_path =~ session_id
      assert preview.message_count >= 1
      assert preview.is_team_session == false
      assert %DateTime{} = preview.last_modified
      assert is_integer(preview.file_size) and preview.file_size > 0
      assert preview.custom_title == "My Session"
      assert preview.summary == "Did stuff"
      assert preview.first_prompt == "hello"
      assert is_boolean(preview.already_imported)

      # TELEMETRY: collect all emitted spans and verify expected ones are present
      spans = collect_spans()

      span_names = Enum.map(spans, &to_string(elem(&1, 6)))
      assert "spotter.transcript_discovery.discover" in span_names
      assert "spotter.transcript_discovery.scan_directory" in span_names
    end
  end

  describe "discover/1 already_imported detection" do
    test "marks already-imported sessions as already_imported: true", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()
      project_dir = Path.join(tmp_dir, "imported-project")
      File.mkdir_p!(project_dir)
      write_jsonl_file(project_dir, session_id)
      write_sessions_index(project_dir, session_id)

      # Insert matching Session into DB
      project =
        Ash.create!(Spotter.Transcripts.Project, %{
          name: "imported-project",
          pattern: "imported"
        })

      Ash.create!(Spotter.Transcripts.Session, %{
        session_id: session_id,
        project_id: project.id,
        cwd: "/home/user/project"
      })

      [preview] = TranscriptDiscovery.discover(tmp_dir)
      assert preview.already_imported == true
    end
  end

  describe "discover/1 empty and edge cases" do
    test "returns empty list for empty directory", %{tmp_dir: tmp_dir} do
      assert TranscriptDiscovery.discover(tmp_dir) == []
    end

    test "skips malformed JSONL files gracefully", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "bad-project")
      File.mkdir_p!(project_dir)

      # Write a malformed JSONL file (invalid JSON)
      File.write!(Path.join(project_dir, "bad-session.jsonl"), "this is not json\n")

      results = TranscriptDiscovery.discover(tmp_dir)
      assert results == []
    end

    test "results are sorted by last_modified descending", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "sort-project")
      File.mkdir_p!(project_dir)

      older_id = Ash.UUID.generate()
      newer_id = Ash.UUID.generate()

      older_path = write_jsonl_file(project_dir, older_id)
      newer_path = write_jsonl_file(project_dir, newer_id)

      # Touch files to control mtime — older file gets past timestamp
      File.touch!(older_path, {{2026, 1, 1}, {0, 0, 0}})
      File.touch!(newer_path, {{2026, 2, 1}, {0, 0, 0}})

      write_sessions_index_multi(project_dir, [
        {older_id, "2026-01-01T00:00:00Z"},
        {newer_id, "2026-02-01T00:00:00Z"}
      ])

      results = TranscriptDiscovery.discover(tmp_dir)
      assert length(results) == 2

      [first, second] = results
      assert DateTime.compare(first.last_modified, second.last_modified) == :gt
    end

    test "project_filter option filters by project name", %{tmp_dir: tmp_dir} do
      dir_a = Path.join(tmp_dir, "alpha-project")
      dir_b = Path.join(tmp_dir, "beta-project")
      File.mkdir_p!(dir_a)
      File.mkdir_p!(dir_b)

      id_a = Ash.UUID.generate()
      id_b = Ash.UUID.generate()

      write_jsonl_file(dir_a, id_a)
      write_sessions_index(dir_a, id_a)
      write_jsonl_file(dir_b, id_b)
      write_sessions_index(dir_b, id_b)

      results =
        TranscriptDiscovery.discover(transcript_roots: [tmp_dir], project_filter: "alpha-project")

      assert length(results) == 1
      assert hd(results).project_name == "alpha-project"
    end

    test "results are capped at 500 entries", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "big-project")
      File.mkdir_p!(project_dir)

      entries =
        for i <- 1..510 do
          id = Ash.UUID.generate()
          write_jsonl_file(project_dir, id)

          {id,
           "2026-01-#{String.pad_leading(Integer.to_string(rem(i, 28) + 1), 2, "0")}T00:00:00Z"}
        end

      write_sessions_index_multi(project_dir, entries)

      results = TranscriptDiscovery.discover(tmp_dir)
      assert length(results) == 500
    end
  end

  describe "list_project_names/0" do
    test "returns sorted unique project names", %{tmp_dir: tmp_dir} do
      for name <- ["zeta-proj", "alpha-proj"] do
        dir = Path.join(tmp_dir, name)
        File.mkdir_p!(dir)
        id = Ash.UUID.generate()
        write_jsonl_file(dir, id)
        write_sessions_index(dir, id)
      end

      assert {:ok, names} = TranscriptDiscovery.list_project_names(transcript_roots: [tmp_dir])
      assert names == ["alpha-proj", "zeta-proj"]
    end

    test "returns {:ok, []} when no transcripts found", %{tmp_dir: tmp_dir} do
      assert {:ok, []} = TranscriptDiscovery.list_project_names(transcript_roots: [tmp_dir])
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

  defp write_sessions_index(dir, session_id) do
    index = %{
      "entries" => [
        %{
          "sessionId" => session_id,
          "customTitle" => "My Session",
          "summary" => "Did stuff",
          "firstPrompt" => "hello",
          "created" => "2026-01-01T00:00:00Z",
          "modified" => "2026-02-01T00:00:00Z"
        }
      ]
    }

    path = Path.join(dir, "sessions-index.json")
    File.write!(path, Jason.encode!(index))
    path
  end

  defp write_sessions_index_multi(dir, entries) do
    index = %{
      "entries" =>
        Enum.map(entries, fn {session_id, modified} ->
          %{
            "sessionId" => session_id,
            "customTitle" => "Session #{String.slice(session_id, 0..7)}",
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
    # Drain all span messages from the process mailbox (allow brief delay for export)
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
