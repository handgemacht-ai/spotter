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
        cwd: "/home/user/project",
        transcript_dir: "imported-project",
        message_count: 2
      })

      [preview] = TranscriptDiscovery.discover(tmp_dir)
      assert preview.already_imported == true
    end

    test "does not mark stub sessions as already imported", %{tmp_dir: tmp_dir} do
      session_id = Ash.UUID.generate()
      project_dir = Path.join(tmp_dir, "stub-project")
      File.mkdir_p!(project_dir)
      write_jsonl_file(project_dir, session_id)
      write_sessions_index(project_dir, session_id)

      project =
        Ash.create!(Spotter.Transcripts.Project, %{
          name: "stub-project",
          pattern: "stub"
        })

      Ash.create!(Spotter.Transcripts.Session, %{
        session_id: session_id,
        project_id: project.id,
        cwd: "/home/user/project"
      })

      [preview] = TranscriptDiscovery.discover(tmp_dir)
      assert preview.already_imported == false
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

  describe "discover/1 team session detection (bug #3)" do
    @tag :import_bug
    test "team lead session (team_name only) is marked is_team_session: true", %{
      tmp_dir: tmp_dir
    } do
      project_dir = Path.join(tmp_dir, "team-project")
      File.mkdir_p!(project_dir)

      lead_id = Ash.UUID.generate()
      write_team_jsonl_file(project_dir, lead_id, team_name: "my-team")
      write_sessions_index(project_dir, lead_id)

      [preview] = TranscriptDiscovery.discover(tmp_dir)
      assert preview.is_team_session == true
    end

    @tag :import_bug
    test "team member session (team_name + agent_name) is distinguishable from lead", %{
      tmp_dir: tmp_dir
    } do
      project_dir = Path.join(tmp_dir, "team-project")
      File.mkdir_p!(project_dir)

      lead_id = Ash.UUID.generate()
      member_id = Ash.UUID.generate()

      write_team_jsonl_file(project_dir, lead_id, team_name: "my-team")
      write_team_jsonl_file(project_dir, member_id, team_name: "my-team", agent_name: "navigator")

      write_sessions_index_multi(project_dir, [
        {lead_id, "2026-02-01T00:00:00Z"},
        {member_id, "2026-02-01T01:00:00Z"}
      ])

      results = TranscriptDiscovery.discover(tmp_dir)
      assert length(results) == 2

      lead = Enum.find(results, &(&1.session_id == lead_id))
      member = Enum.find(results, &(&1.session_id == member_id))

      # Both should be marked as team sessions
      assert lead.is_team_session == true
      assert member.is_team_session == true

      # BUG #3: There is no way to distinguish team lead from team member.
      # The preview map should include team role information so the UI can
      # filter or label member sessions differently from lead sessions.
      # This assertion will fail until the preview map includes team role data.
      assert Map.has_key?(member, :is_team_member),
             "Expected preview to include :is_team_member field to distinguish " <>
               "team lead sessions from team member sessions (bug #3)"
    end
  end

  describe "discover/1 team_name extraction (s0p.1)" do
    test "build_preview includes team_name extracted from first JSONL line teamName field", %{
      tmp_dir: tmp_dir
    } do
      project_dir = Path.join(tmp_dir, "team-name-project")
      File.mkdir_p!(project_dir)

      session_id = Ash.UUID.generate()

      write_team_jsonl_file(project_dir, session_id, team_name: "impl-s0p")
      write_sessions_index(project_dir, session_id)

      [preview] = TranscriptDiscovery.discover(tmp_dir)

      assert preview.team_name == "impl-s0p",
             "Expected preview to include team_name field extracted from JSONL teamName. " <>
               "Got: #{inspect(Map.get(preview, :team_name, :missing_key))}"
    end

    test "team_name is nil for non-team sessions", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "solo-project")
      File.mkdir_p!(project_dir)

      session_id = Ash.UUID.generate()

      write_jsonl_file(project_dir, session_id)
      write_sessions_index(project_dir, session_id)

      [preview] = TranscriptDiscovery.discover(tmp_dir)

      assert Map.has_key?(preview, :team_name),
             "Expected preview map to always include :team_name key"

      assert preview.team_name == nil,
             "Expected team_name to be nil for non-team sessions, got: #{inspect(preview.team_name)}"
    end
  end

  describe "group_by_team/1 (s0p.1)" do
    test "groups previews by team_name", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "team-group-project")
      File.mkdir_p!(project_dir)

      lead_id = Ash.UUID.generate()
      member_id = Ash.UUID.generate()

      write_team_jsonl_file(project_dir, lead_id, team_name: "impl-abc")

      write_team_jsonl_file(project_dir, member_id,
        team_name: "impl-abc",
        agent_name: "navigator"
      )

      write_sessions_index_multi(project_dir, [
        {lead_id, "2026-02-01T00:00:00Z"},
        {member_id, "2026-02-01T01:00:00Z"}
      ])

      previews = TranscriptDiscovery.discover(tmp_dir)
      grouped = TranscriptDiscovery.group_by_team(previews)

      assert Map.has_key?(grouped, "impl-abc")
      assert length(grouped["impl-abc"]) == 2
    end

    test "non-team sessions (team_name: nil) are excluded from grouping", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "mixed-project")
      File.mkdir_p!(project_dir)

      solo_id = Ash.UUID.generate()
      team_id = Ash.UUID.generate()

      write_jsonl_file(project_dir, solo_id)
      write_team_jsonl_file(project_dir, team_id, team_name: "my-team")

      write_sessions_index_multi(project_dir, [
        {solo_id, "2026-02-01T00:00:00Z"},
        {team_id, "2026-02-01T01:00:00Z"}
      ])

      previews = TranscriptDiscovery.discover(tmp_dir)
      grouped = TranscriptDiscovery.group_by_team(previews)

      # Only the team session should be grouped
      assert Map.keys(grouped) == ["my-team"]
      assert length(grouped["my-team"]) == 1

      # nil key should not exist
      refute Map.has_key?(grouped, nil)
    end
  end

  describe "discover/1 team detection with real camelCase JSONL keys (bug #2)" do
    @tag :import_bug
    test "detects team session when JSONL uses teamName (camelCase) like real Claude Code files",
         %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "real-team-project")
      File.mkdir_p!(project_dir)

      session_id = Ash.UUID.generate()

      # Real Claude Code JSONL files use camelCase: "teamName", "agentName"
      # NOT snake_case "team_name", "agent_name"
      write_real_team_jsonl_file(project_dir, session_id,
        team_name: "debug-team-sessions",
        agent_name: nil
      )

      write_sessions_index(project_dir, session_id)

      [preview] = TranscriptDiscovery.discover(tmp_dir)

      assert preview.is_team_session == true,
             ~s(Expected is_team_session to be true when JSONL first line contains "teamName" [camelCase]. detect_team/2 likely checks "team_name" [snake_case] which never matches real JSONL files.)
    end

    @tag :import_bug
    test "detects team member when JSONL uses agentName (camelCase) like real Claude Code files",
         %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "real-team-project")
      File.mkdir_p!(project_dir)

      session_id = Ash.UUID.generate()

      write_real_team_jsonl_file(project_dir, session_id,
        team_name: "debug-team-sessions",
        agent_name: "navigator-core"
      )

      write_sessions_index(project_dir, session_id)

      [preview] = TranscriptDiscovery.discover(tmp_dir)

      assert preview.is_team_session == true

      assert preview.is_team_member == true,
             ~s(Expected is_team_member to be true when JSONL first line contains "agentName" [camelCase]. build_preview reads parsed["agentName"] but detect_team must first recognize the session as a team session.)
    end
  end

  describe "discover/1 multi-root scanning" do
    test "scans multiple roots and returns results from all of them", %{tmp_dir: tmp_dir} do
      root_a = Path.join(tmp_dir, "root_claude")
      root_b = Path.join(tmp_dir, "root_agents")

      project_a = Path.join(root_a, "my-project")
      project_b = Path.join(root_b, "other-project")
      File.mkdir_p!(project_a)
      File.mkdir_p!(project_b)

      id_a = Ash.UUID.generate()
      id_b = Ash.UUID.generate()

      write_jsonl_file(project_a, id_a)
      write_sessions_index(project_a, id_a)
      write_jsonl_file(project_b, id_b)
      write_sessions_index(project_b, id_b)

      results = TranscriptDiscovery.discover(transcript_roots: [root_a, root_b])

      assert length(results) == 2

      session_ids = Enum.map(results, & &1.session_id) |> MapSet.new()
      assert MapSet.member?(session_ids, id_a)
      assert MapSet.member?(session_ids, id_b)

      project_names = Enum.map(results, & &1.project_name) |> MapSet.new()
      assert MapSet.member?(project_names, "my-project")
      assert MapSet.member?(project_names, "other-project")
    end

    test "same project dir name under multiple roots returns sessions from both", %{
      tmp_dir: tmp_dir
    } do
      root_a = Path.join(tmp_dir, "root_claude")
      root_b = Path.join(tmp_dir, "root_agents")

      # Same project name "shared-project" in both roots
      project_a = Path.join(root_a, "shared-project")
      project_b = Path.join(root_b, "shared-project")
      File.mkdir_p!(project_a)
      File.mkdir_p!(project_b)

      id_a = Ash.UUID.generate()
      id_b = Ash.UUID.generate()

      write_jsonl_file(project_a, id_a)
      write_sessions_index(project_a, id_a)
      write_jsonl_file(project_b, id_b)
      write_sessions_index(project_b, id_b)

      results = TranscriptDiscovery.discover(transcript_roots: [root_a, root_b])

      assert length(results) == 2

      # Both sessions should have the same project_name
      assert Enum.all?(results, &(&1.project_name == "shared-project"))

      # But different project_dir paths (distinguishing which root they came from)
      dirs = Enum.map(results, & &1.project_dir) |> MapSet.new()
      assert MapSet.size(dirs) == 2
      assert MapSet.member?(dirs, project_a)
      assert MapSet.member?(dirs, project_b)
    end

    test "sessions-index metadata in one root but missing in another", %{tmp_dir: tmp_dir} do
      root_a = Path.join(tmp_dir, "root_with_index")
      root_b = Path.join(tmp_dir, "root_without_index")

      project_a = Path.join(root_a, "indexed-project")
      project_b = Path.join(root_b, "bare-project")
      File.mkdir_p!(project_a)
      File.mkdir_p!(project_b)

      id_a = Ash.UUID.generate()
      id_b = Ash.UUID.generate()

      write_jsonl_file(project_a, id_a)
      write_sessions_index(project_a, id_a)

      # Root B has a JSONL file but NO sessions-index.json
      write_jsonl_file(project_b, id_b)

      results = TranscriptDiscovery.discover(transcript_roots: [root_a, root_b])

      assert length(results) == 2

      indexed = Enum.find(results, &(&1.session_id == id_a))
      bare = Enum.find(results, &(&1.session_id == id_b))

      # Session from root with index has metadata
      assert indexed.custom_title == "My Session"
      assert indexed.summary == "Did stuff"

      # Session from root without index has nil metadata
      assert bare.custom_title == nil
      assert bare.summary == nil
    end

    test "deduplicates when same session_id appears under multiple roots, preferring first root",
         %{tmp_dir: tmp_dir} do
      root_a = Path.join(tmp_dir, "root_primary")
      root_b = Path.join(tmp_dir, "root_secondary")

      project_a = Path.join(root_a, "dup-project")
      project_b = Path.join(root_b, "dup-project")
      File.mkdir_p!(project_a)
      File.mkdir_p!(project_b)

      # Same session_id written to both roots
      shared_id = Ash.UUID.generate()

      write_jsonl_file(project_a, shared_id)
      write_sessions_index(project_a, shared_id)
      write_jsonl_file(project_b, shared_id)
      write_sessions_index(project_b, shared_id)

      results = TranscriptDiscovery.discover(transcript_roots: [root_a, root_b])

      # Same session_id in two roots — discovery should deduplicate
      matching = Enum.filter(results, &(&1.session_id == shared_id))

      assert length(matching) == 1,
             "Expected deduplication of same session_id across roots, " <>
               "got #{length(matching)} entries"

      # Deterministic ordering: first-configured root wins
      [kept] = matching

      assert kept.project_dir == project_a,
             "Expected entry from first-configured root (#{project_a}), " <>
               "got #{kept.project_dir}"
    end

    test "nonexistent root is silently skipped", %{tmp_dir: tmp_dir} do
      real_root = Path.join(tmp_dir, "real_root")
      project = Path.join(real_root, "real-project")
      File.mkdir_p!(project)

      id = Ash.UUID.generate()
      write_jsonl_file(project, id)
      write_sessions_index(project, id)

      bogus_root = Path.join(tmp_dir, "does_not_exist")

      results = TranscriptDiscovery.discover(transcript_roots: [real_root, bogus_root])

      assert length(results) == 1
      assert hd(results).session_id == id
    end
  end

  describe "discover/0 defaults to config transcript_roots" do
    test "reads transcript_roots from DB setting when no opts given", %{tmp_dir: tmp_dir} do
      project_dir = Path.join(tmp_dir, "config-project")
      File.mkdir_p!(project_dir)

      id = Ash.UUID.generate()
      write_jsonl_file(project_dir, id)
      write_sessions_index(project_dir, id)

      # Set transcript_roots in DB so discover/0 picks it up
      Ash.create!(Spotter.Config.Setting, %{
        key: "transcript_roots",
        value: Jason.encode!([tmp_dir])
      })

      results = TranscriptDiscovery.discover()

      matching = Enum.filter(results, &(&1.session_id == id))
      assert length(matching) == 1, "Expected discover/0 to use transcript_roots from DB config"
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

  defp write_team_jsonl_file(dir, session_id, opts) do
    team_name = Keyword.fetch!(opts, :team_name)
    agent_name = Keyword.get(opts, :agent_name)

    first_line =
      %{
        "type" => "system",
        "sessionId" => session_id,
        "cwd" => "/home/user/project",
        "version" => "1.0",
        "teamName" => team_name
      }
      |> then(fn m ->
        if agent_name, do: Map.put(m, "agentName", agent_name), else: m
      end)

    lines = [
      first_line,
      %{
        "type" => "human",
        "role" => "user",
        "sessionId" => session_id,
        "content" => [%{"type" => "text", "text" => "hello team"}],
        "timestamp" => "2026-02-01T12:00:01Z"
      }
    ]

    path = Path.join(dir, "#{session_id}.jsonl")
    File.write!(path, Enum.map_join(lines, "\n", &Jason.encode!/1))
    path
  end

  defp write_real_team_jsonl_file(dir, session_id, opts) do
    team_name = Keyword.fetch!(opts, :team_name)
    agent_name = Keyword.get(opts, :agent_name)

    # Use camelCase keys matching real Claude Code JSONL output
    first_line =
      %{
        "type" => "system",
        "sessionId" => session_id,
        "cwd" => "/home/user/project",
        "version" => "1.0",
        "teamName" => team_name
      }
      |> then(fn m ->
        if agent_name, do: Map.put(m, "agentName", agent_name), else: m
      end)

    lines = [
      first_line,
      %{
        "type" => "human",
        "role" => "user",
        "sessionId" => session_id,
        "content" => [%{"type" => "text", "text" => "hello team"}],
        "timestamp" => "2026-02-01T12:00:01Z"
      }
    ]

    path = Path.join(dir, "#{session_id}.jsonl")
    File.write!(path, Enum.map_join(lines, "\n", &Jason.encode!/1))
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
