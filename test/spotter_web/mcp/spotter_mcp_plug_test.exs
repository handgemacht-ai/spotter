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

  defp mcp_post_with_project_dir(body, session_id, project_dir) do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("x-spotter-project-dir", project_dir)

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
    test "returns scoped tool names without list_projects" do
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

      refute "list_projects" in tool_names
      assert "list_sessions" in tool_names
      assert "list_review_annotations" in tool_names
      assert "resolve_annotation" in tool_names
    end

    test "list_sessions schema includes project_id filter" do
      {_body, session_id} = initialize()

      {200, body, _conn} =
        mcp_post(
          %{
            "jsonrpc" => "2.0",
            "id" => 20,
            "method" => "tools/list",
            "params" => %{}
          },
          session_id
        )

      tools = body["result"]["tools"]

      list_sessions = Enum.find(tools, &(&1["name"] == "list_sessions"))
      assert list_sessions != nil

      filter_props =
        get_in(list_sessions, ["inputSchema", "properties", "filter", "properties"])

      assert filter_props != nil
      assert Map.has_key?(filter_props, "project_id")
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

  describe "project scope resolution from x-spotter-project-dir header" do
    test "valid header resolves project scope in Ash context", %{project: project} do
      project_dir = "test-mcp-project"

      {_body, session_id} = initialize()

      {200, _body, conn} =
        mcp_post_with_project_dir(
          %{
            "jsonrpc" => "2.0",
            "id" => 100,
            "method" => "tools/list",
            "params" => %{}
          },
          session_id,
          project_dir
        )

      ash_context = get_in(conn.private, [:ash, :context]) || %{}
      scope = ash_context[:spotter_mcp_scope]
      assert scope != nil
      assert scope.project_id == project.id
      assert scope.project_dir == project_dir
    end

    test "missing header sets scope error context" do
      {_body, session_id} = initialize()

      {200, _body, conn} =
        mcp_post(
          %{
            "jsonrpc" => "2.0",
            "id" => 101,
            "method" => "tools/list",
            "params" => %{}
          },
          session_id
        )

      ash_context = get_in(conn.private, [:ash, :context]) || %{}
      assert ash_context[:spotter_mcp_scope_error] == "missing_header"
    end

    test "unmatched header sets scope error context" do
      {_body, session_id} = initialize()

      {200, _body, conn} =
        mcp_post_with_project_dir(
          %{
            "jsonrpc" => "2.0",
            "id" => 102,
            "method" => "tools/list",
            "params" => %{}
          },
          session_id,
          "/no-match-whatsoever"
        )

      ash_context = get_in(conn.private, [:ash, :context]) || %{}
      assert ash_context[:spotter_mcp_scope_error] != nil
      assert ash_context[:spotter_mcp_scope] == nil
    end

    test "scoped list_sessions only returns sessions for scoped project", %{project: project} do
      project_dir = "test-mcp-project"

      {_body, session_id} = initialize()

      {200, body, _conn} =
        mcp_post_with_project_dir(
          %{
            "jsonrpc" => "2.0",
            "id" => 103,
            "method" => "tools/call",
            "params" => %{
              "name" => "list_sessions",
              "arguments" => %{}
            }
          },
          session_id,
          project_dir
        )

      result = body["result"]
      assert result["isError"] in [false, nil]

      [content | _] = result["content"]
      decoded = Jason.decode!(content["text"])
      assert is_list(decoded)

      Enum.each(decoded, fn session ->
        assert session["project_id"] == project.id
      end)
    end

    test "missing scope causes list_sessions to return error" do
      {_body, session_id} = initialize()

      {200, body, _conn} =
        mcp_post(
          %{
            "jsonrpc" => "2.0",
            "id" => 104,
            "method" => "tools/call",
            "params" => %{
              "name" => "list_sessions",
              "arguments" => %{}
            }
          },
          session_id
        )

      # AshAi returns scope errors as isError result or JSON-RPC error
      cond do
        body["result"] != nil ->
          assert body["result"]["isError"] == true

        body["error"] != nil ->
          assert is_binary(body["error"]["message"])
      end
    end
  end

  describe "tools/call" do
    test "list_sessions returns scoped sessions", %{project: project} do
      {_body, session_id} = initialize()

      {200, body, _conn} =
        mcp_post_with_project_dir(
          %{
            "jsonrpc" => "2.0",
            "id" => 11,
            "method" => "tools/call",
            "params" => %{
              "name" => "list_sessions",
              "arguments" => %{}
            }
          },
          session_id,
          "test-mcp-project"
        )

      result = body["result"]
      assert result["isError"] in [false, nil]

      [content | _] = result["content"]
      decoded = Jason.decode!(content["text"])
      assert is_list(decoded)

      Enum.each(decoded, fn session ->
        assert session["project_id"] == project.id
      end)
    end

    test "list_review_annotations output includes public fields", %{
      session: session,
      project: project
    } do
      Ash.create!(Annotation, %{
        session_id: session.id,
        source: :transcript,
        selected_text: "check this",
        comment: "review comment",
        purpose: :review,
        state: :open,
        project_id: project.id
      })

      {_body, session_id} = initialize()

      {200, body, _conn} =
        mcp_post_with_project_dir(
          %{
            "jsonrpc" => "2.0",
            "id" => 12,
            "method" => "tools/call",
            "params" => %{
              "name" => "list_review_annotations",
              "arguments" => %{}
            }
          },
          session_id,
          "test-mcp-project"
        )

      [content | _] = body["result"]["content"]
      [annotation | _] = Jason.decode!(content["text"])

      assert annotation["state"] != nil
      assert annotation["purpose"] != nil
      assert annotation["source"] != nil
      assert annotation["selected_text"] != nil
      assert annotation["comment"] != nil
      assert annotation["inserted_at"] != nil
    end

    test "list_review_annotations excludes purpose=explain", %{
      session: session,
      project: project
    } do
      review =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :transcript,
          selected_text: "review item",
          comment: "needs review",
          purpose: :review,
          state: :open,
          project_id: project.id
        })

      _explain =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :transcript,
          selected_text: "explain item",
          comment: "explanation",
          purpose: :explain,
          state: :open,
          project_id: project.id
        })

      {_body, session_id} = initialize()

      {200, body, _conn} =
        mcp_post_with_project_dir(
          %{
            "jsonrpc" => "2.0",
            "id" => 14,
            "method" => "tools/call",
            "params" => %{
              "name" => "list_review_annotations",
              "arguments" => %{}
            }
          },
          session_id,
          "test-mcp-project"
        )

      [content | _] = body["result"]["content"]
      annotations = Jason.decode!(content["text"])

      ids = Enum.map(annotations, & &1["id"])
      assert review.id in ids
      purposes = Enum.map(annotations, & &1["purpose"])
      refute "explain" in purposes
    end

    test "tool call with invalid filter returns error", %{} do
      {_body, session_id} = initialize()

      {200, body, _conn} =
        mcp_post_with_project_dir(
          %{
            "jsonrpc" => "2.0",
            "id" => 15,
            "method" => "tools/call",
            "params" => %{
              "name" => "list_sessions",
              "arguments" => %{"filter" => %{"cwd" => %{"eq" => "/fake"}}}
            }
          },
          session_id,
          "test-mcp-project"
        )

      # AshAi returns tool errors as isError result or JSON-RPC error
      cond do
        body["result"] != nil ->
          assert body["result"]["isError"] == true
          [content | _] = body["result"]["content"]
          assert content["type"] == "text"

        body["error"] != nil ->
          assert is_binary(body["error"]["message"])
          assert body["error"]["code"] != nil
      end
    end

    test "resolve_annotation updates state and writes metadata", %{
      session: session,
      project: project
    } do
      annotation =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :transcript,
          selected_text: "fix this",
          comment: "needs work",
          project_id: project.id
        })

      {_body, session_id} = initialize()

      {200, body, _conn} =
        mcp_post_with_project_dir(
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
          session_id,
          "test-mcp-project"
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
