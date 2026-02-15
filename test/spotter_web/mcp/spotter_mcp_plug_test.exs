defmodule SpotterWeb.SpotterMcpPlugTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Annotation, Project, Session}

  @endpoint SpotterWeb.Endpoint

  setup do
    Sandbox.checkout(Spotter.Repo)

    project = Ash.create!(Project, %{name: "test-mcp", pattern: "^test"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

    %{project: project, session: session}
  end

  defp mcp_post(body, session_id \\ nil) do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("content-type", "application/json")

    conn =
      if session_id,
        do: Plug.Conn.put_req_header(conn, "mcp-session-id", session_id),
        else: conn

    conn = Phoenix.ConnTest.dispatch(conn, @endpoint, :post, "/api/mcp", body)
    {conn.status, Jason.decode!(conn.resp_body), conn}
  end

  defp initialize do
    {200, body, conn} =
      mcp_post(%{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-03-26",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "test", "version" => "1.0.0"}
        }
      })

    session_id =
      Plug.Conn.get_resp_header(conn, "mcp-session-id")
      |> List.first()

    {body, session_id}
  end

  describe "initialize" do
    test "returns 200 and sets mcp-session-id header" do
      {body, session_id} = initialize()

      assert body["result"]["serverInfo"]["name"] == "Spotter"
      assert session_id != nil
    end
  end

  describe "tools/list" do
    test "returns all four tool names" do
      {_body, session_id} = initialize()

      {200, body, _conn} =
        mcp_post(
          %{
            "jsonrpc" => "2.0",
            "id" => 2,
            "method" => "tools/list",
            "params" => %{}
          },
          session_id
        )

      tool_names = Enum.map(body["result"]["tools"], & &1["name"]) |> Enum.sort()

      assert "list_projects" in tool_names
      assert "list_sessions" in tool_names
      assert "list_review_annotations" in tool_names
      assert "resolve_annotation" in tool_names
    end
  end

  defp mcp_get(headers \\ []) do
    conn =
      Enum.reduce(headers, Phoenix.ConnTest.build_conn(), fn {key, val}, acc ->
        Plug.Conn.put_req_header(acc, key, val)
      end)

    conn = Phoenix.ConnTest.dispatch(conn, @endpoint, :get, "/api/mcp", nil)
    {conn.status, conn.resp_body, conn}
  end

  describe "GET /api/mcp (SSE)" do
    test "returns 200 with endpoint event when Accept: text/event-stream" do
      {status, body, conn} = mcp_get([{"accept", "text/event-stream"}])

      assert status == 200

      content_type =
        Plug.Conn.get_resp_header(conn, "content-type") |> List.first("")

      assert content_type =~ "text/event-stream"
      assert body =~ "event: endpoint"
      assert body =~ "/api/mcp"
    end
  end

  describe "GET /api/mcp (non-SSE)" do
    test "returns 204 with empty body when no SSE accept header" do
      {status, body, _conn} = mcp_get([{"accept", "*/*"}])

      assert status == 204
      assert body == ""
    end

    test "returns 204 when no accept header is set" do
      {status, body, _conn} = mcp_get()

      assert status == 204
      assert body == ""
    end
  end

  describe "tools/call" do
    test "list_projects returns JSON text content", %{project: _project} do
      {_body, session_id} = initialize()

      {200, body, _conn} =
        mcp_post(
          %{
            "jsonrpc" => "2.0",
            "id" => 3,
            "method" => "tools/call",
            "params" => %{
              "name" => "list_projects",
              "arguments" => %{}
            }
          },
          session_id
        )

      result = body["result"]
      assert result["isError"] == false

      [content | _] = result["content"]
      assert content["type"] == "text"

      decoded = Jason.decode!(content["text"])
      assert is_list(decoded)
      assert decoded != []
    end

    test "resolve_annotation updates state and writes metadata", %{session: session} do
      annotation =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :transcript,
          selected_text: "fix this",
          comment: "needs work"
        })

      {_body, session_id} = initialize()

      {200, body, _conn} =
        mcp_post(
          %{
            "jsonrpc" => "2.0",
            "id" => 4,
            "method" => "tools/call",
            "params" => %{
              "name" => "resolve_annotation",
              "arguments" => %{
                "id" => annotation.id,
                "input" => %{
                  "resolution" => "Fixed the code",
                  "resolution_kind" => "code_change"
                }
              }
            }
          },
          session_id
        )

      result = body["result"]
      assert result != nil, "Expected result but got: #{inspect(body)}"
      assert result["isError"] in [false, nil]

      updated = Ash.get!(Annotation, annotation.id)
      assert updated.state == :closed
      assert updated.metadata["resolution"] == "Fixed the code"
      assert updated.metadata["resolution_kind"] == "code_change"
      assert updated.metadata["resolved_at"] != nil
    end
  end
end
