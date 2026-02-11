defmodule SpotterWeb.HooksControllerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Project, Session}

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

  defp post_snapshot(params) do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Phoenix.ConnTest.dispatch(@endpoint, :post, "/api/hooks/file-snapshot", params)

    {conn.status, Jason.decode!(conn.resp_body)}
  end

  describe "POST /api/hooks/file-snapshot" do
    test "creates snapshot with valid params", %{session: session} do
      {status, body} =
        post_snapshot(%{
          "session_id" => session.session_id,
          "tool_use_id" => "tool_abc",
          "file_path" => "/tmp/test.ex",
          "relative_path" => "test.ex",
          "content_before" => nil,
          "content_after" => "defmodule Test do\nend",
          "change_type" => "created",
          "source" => "write",
          "timestamp" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert status == 201
      assert body["ok"] == true

      snapshots = Ash.read!(Spotter.Transcripts.FileSnapshot)
      assert length(snapshots) == 1
      assert hd(snapshots).tool_use_id == "tool_abc"
      assert hd(snapshots).change_type == :created
      assert hd(snapshots).source == :write
    end

    test "returns 404 for unknown session" do
      {status, body} =
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
      {status, body} =
        post_snapshot(%{
          "tool_use_id" => "tool_abc",
          "file_path" => "/tmp/test.ex"
        })

      assert status == 400
      assert body["error"] =~ "session_id is required"
    end

    test "returns 400 for invalid change_type atom", %{session: session} do
      {status, body} =
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
  end
end
