defmodule SpotterWeb.HooksControllerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Commit, Project, Session, SessionCommitLink}

  require Ash.Query

  @endpoint SpotterWeb.Endpoint

  setup do
    Sandbox.checkout(Spotter.Repo)

    project = Ash.create!(Project, %{name: "test-hooks", pattern: "^test"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

    %{session: session}
  end

  @valid_traceparent "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
  @malformed_traceparent "not-a-valid-traceparent"

  defp post_snapshot(params, headers \\ []) do
    conn =
      Enum.reduce(headers, Phoenix.ConnTest.build_conn(), fn {k, v}, conn ->
        Plug.Conn.put_req_header(conn, k, v)
      end)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Phoenix.ConnTest.dispatch(@endpoint, :post, "/api/hooks/file-snapshot", params)

    {conn.status, Jason.decode!(conn.resp_body), conn}
  end

  defp snapshot_params(session) do
    %{
      "session_id" => session.session_id,
      "tool_use_id" => "tool_abc",
      "file_path" => "/tmp/test.ex",
      "relative_path" => "test.ex",
      "content_before" => nil,
      "content_after" => "defmodule Test do\nend",
      "change_type" => "created",
      "source" => "write",
      "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  describe "POST /api/hooks/file-snapshot" do
    test "creates snapshot with valid params", %{session: session} do
      {status, body, _conn} = post_snapshot(snapshot_params(session))

      assert status == 201
      assert body["ok"] == true

      snapshots = Ash.read!(Spotter.Transcripts.FileSnapshot)
      assert length(snapshots) == 1
      assert hd(snapshots).tool_use_id == "tool_abc"
      assert hd(snapshots).change_type == :created
      assert hd(snapshots).source == :write
    end

    test "returns 404 for unknown session" do
      {status, body, _conn} =
        post_snapshot(%{
          "session_id" => Ash.UUID.generate(),
          "tool_use_id" => "tool_abc",
          "file_path" => "/tmp/test.ex",
          "change_type" => "created",
          "source" => "write",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert status == 404
      assert body["error"] =~ "session not found"
    end

    test "returns 400 for missing session_id" do
      {status, body, _conn} =
        post_snapshot(%{
          "tool_use_id" => "tool_abc",
          "file_path" => "/tmp/test.ex"
        })

      assert status == 400
      assert body["error"] =~ "session_id is required"
    end

    test "returns 400 for invalid change_type atom", %{session: session} do
      {status, body, _conn} =
        post_snapshot(%{
          "session_id" => session.session_id,
          "tool_use_id" => "tool_abc",
          "file_path" => "/tmp/test.ex",
          "change_type" => "nonexistent_atom_xyz",
          "source" => "write",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert status == 400
      assert body["error"] =~ "invalid change_type"
    end

    test "succeeds with valid traceparent header", %{session: session} do
      {status, body, conn} =
        post_snapshot(snapshot_params(session), [{"traceparent", @valid_traceparent}])

      assert status == 201
      assert body["ok"] == true
      assert Plug.Conn.get_resp_header(conn, "x-spotter-trace-id") != []
    end

    test "succeeds with malformed traceparent header", %{session: session} do
      {status, body, _conn} =
        post_snapshot(snapshot_params(session), [{"traceparent", @malformed_traceparent}])

      assert status == 201
      assert body["ok"] == true
    end

    test "succeeds without traceparent header", %{session: session} do
      {status, body, _conn} = post_snapshot(snapshot_params(session))

      assert status == 201
      assert body["ok"] == true
    end
  end

  describe "file_snapshot relative_path derivation" do
    test "derives relative_path from absolute file_path using session cwd", %{session: _session} do
      project = Ash.create!(Project, %{name: "test-derive", pattern: "^derive"})

      session_with_cwd =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "test-dir",
          cwd: "/repo",
          project_id: project.id
        })

      {status, body, _conn} =
        post_snapshot(%{
          "session_id" => session_with_cwd.session_id,
          "tool_use_id" => "tool_derive",
          "file_path" => "/repo/lib/a.ex",
          "content_after" => "defmodule A do\nend",
          "change_type" => "created",
          "source" => "write",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert status == 201
      assert body["ok"] == true

      snapshot =
        Spotter.Transcripts.FileSnapshot
        |> Ash.Query.filter(tool_use_id == "tool_derive")
        |> Ash.read!()
        |> List.first()

      assert snapshot.relative_path == "lib/a.ex"
    end

    test "keeps explicit relative_path when provided", %{session: session} do
      {status, _body, _conn} =
        post_snapshot(%{
          "session_id" => session.session_id,
          "tool_use_id" => "tool_explicit",
          "file_path" => "/repo/lib/a.ex",
          "relative_path" => "custom/path.ex",
          "content_after" => "defmodule A do\nend",
          "change_type" => "created",
          "source" => "write",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert status == 201

      snapshot =
        Spotter.Transcripts.FileSnapshot
        |> Ash.Query.filter(tool_use_id == "tool_explicit")
        |> Ash.read!()
        |> List.first()

      assert snapshot.relative_path == "custom/path.ex"
    end

    test "uses file_path directly when it is relative", %{session: session} do
      {status, _body, _conn} =
        post_snapshot(%{
          "session_id" => session.session_id,
          "tool_use_id" => "tool_relative",
          "file_path" => "lib/b.ex",
          "content_after" => "defmodule B do\nend",
          "change_type" => "created",
          "source" => "write",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert status == 201

      snapshot =
        Spotter.Transcripts.FileSnapshot
        |> Ash.Query.filter(tool_use_id == "tool_relative")
        |> Ash.read!()
        |> List.first()

      assert snapshot.relative_path == "lib/b.ex"
    end
  end

  defp post_commit_event(params, headers \\ []) do
    conn =
      Enum.reduce(headers, Phoenix.ConnTest.build_conn(), fn {k, v}, conn ->
        Plug.Conn.put_req_header(conn, k, v)
      end)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Phoenix.ConnTest.dispatch(@endpoint, :post, "/api/hooks/commit-event", params)

    {conn.status, Jason.decode!(conn.resp_body), conn}
  end

  defp commit_event_params(session) do
    hash = String.duplicate("a", 40)

    %{
      "session_id" => session.session_id,
      "tool_use_id" => "tool_xyz",
      "new_commit_hashes" => [hash],
      "base_head" => String.duplicate("0", 40),
      "head" => hash,
      "captured_at" => DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  describe "POST /api/hooks/commit-event" do
    test "ingests commits and enqueues analyze job", %{session: session} do
      hash = String.duplicate("a", 40)

      {status, body, _conn} =
        post_commit_event(%{
          "session_id" => session.session_id,
          "tool_use_id" => "tool_xyz",
          "new_commit_hashes" => [hash],
          "base_head" => String.duplicate("0", 40),
          "head" => hash,
          "captured_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert status == 201
      assert body["ok"] == true
      assert body["ingested"] == 1

      assert [commit] = Ash.read!(Commit)
      assert commit.commit_hash == hash

      assert [link] = Ash.read!(SessionCommitLink)
      assert link.link_type == :observed_in_session
      assert link.confidence == 1.0

      # Verify AnalyzeCommitHotspots job was enqueued
      import Ecto.Query

      assert [_job] =
               Spotter.Repo.all(
                 from(j in Oban.Job,
                   where: j.worker == "Spotter.Transcripts.Jobs.AnalyzeCommitHotspots"
                 )
               )
    end

    test "handles empty hashes array", %{session: session} do
      {status, body, _conn} =
        post_commit_event(%{
          "session_id" => session.session_id,
          "tool_use_id" => "tool_xyz",
          "new_commit_hashes" => []
        })

      assert status == 201
      assert body["ingested"] == 0
    end

    test "is idempotent on duplicate delivery", %{session: session} do
      hash = String.duplicate("d", 40)

      params = %{
        "session_id" => session.session_id,
        "tool_use_id" => "tool_xyz",
        "new_commit_hashes" => [hash]
      }

      {201, _, _} = post_commit_event(params)
      {201, _, _} = post_commit_event(params)

      assert length(Ash.read!(Commit)) == 1
      assert length(Ash.read!(SessionCommitLink)) == 1
    end

    test "returns 404 for unknown session" do
      {status, body, _conn} =
        post_commit_event(%{
          "session_id" => Ash.UUID.generate(),
          "tool_use_id" => "tool_xyz",
          "new_commit_hashes" => [String.duplicate("e", 40)]
        })

      assert status == 404
      assert body["error"] =~ "session not found"
    end

    test "returns 400 for invalid hash format", %{session: session} do
      {status, body, _conn} =
        post_commit_event(%{
          "session_id" => session.session_id,
          "tool_use_id" => "tool_xyz",
          "new_commit_hashes" => ["not-a-hash"]
        })

      assert status == 400
      assert body["error"] =~ "invalid commit hash"
    end

    test "returns 400 for too many hashes", %{session: session} do
      hashes = for i <- 1..51, do: String.pad_leading("#{i}", 40, "0")

      {status, body, _conn} =
        post_commit_event(%{
          "session_id" => session.session_id,
          "tool_use_id" => "tool_xyz",
          "new_commit_hashes" => hashes
        })

      assert status == 400
      assert body["error"] =~ "too many"
    end

    test "returns 400 for missing required fields" do
      {status, body, _conn} = post_commit_event(%{"session_id" => "abc"})

      assert status == 400
      assert body["error"] =~ "required"
    end

    test "succeeds with valid traceparent header", %{session: session} do
      {status, body, conn} =
        post_commit_event(commit_event_params(session), [{"traceparent", @valid_traceparent}])

      assert status == 201
      assert body["ok"] == true
      assert Plug.Conn.get_resp_header(conn, "x-spotter-trace-id") != []
    end

    test "succeeds with malformed traceparent header", %{session: session} do
      {status, body, _conn} =
        post_commit_event(commit_event_params(session), [
          {"traceparent", @malformed_traceparent}
        ])

      assert status == 201
      assert body["ok"] == true
    end

    test "succeeds without traceparent header", %{session: session} do
      {status, body, _conn} = post_commit_event(commit_event_params(session))

      assert status == 201
      assert body["ok"] == true
    end
  end
end
