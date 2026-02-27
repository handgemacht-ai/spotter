defmodule SpotterWeb.SpotterMcpPlugTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Transcripts.{Annotation, Commit, CommitHotspot, Project, RetroSubmission, Session}

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

  defp mcp_post_with_session_id(body, mcp_session_id, spotter_session_id) do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("content-type", "application/json")

    conn =
      if mcp_session_id,
        do: Plug.Conn.put_req_header(conn, "mcp-session-id", mcp_session_id),
        else: conn

    path = "/api/mcp?session_id=#{spotter_session_id}"
    conn = Phoenix.ConnTest.dispatch(conn, @endpoint, :post, path, body)
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
    test "returns only retained tools and excludes pruned tools" do
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

      # Exact retained tool set — no more, no less
      assert tool_names == [
               "create_hotspot",
               "list_review_annotations",
               "resolve_annotation",
               "submit_retro"
             ]

      # Pruned tools must be absent
      refute "list_sessions" in tool_names
      refute "list_hotspots" in tool_names
      refute "list_retros" in tool_names
      refute "rate_retro_item" in tool_names

      # list_projects was already removed
      refute "list_projects" in tool_names
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

    test "missing header falls back to recent session project", %{project: project} do
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
      scope = ash_context[:spotter_mcp_scope]
      assert scope != nil
      assert scope.project_id == project.id
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
  end

  describe "project scope resolution from session_id query param" do
    test "session_id query param resolves project scope", %{session: session, project: project} do
      {_body, mcp_session_id} = initialize()

      {200, _body, conn} =
        mcp_post_with_session_id(
          %{
            "jsonrpc" => "2.0",
            "id" => 200,
            "method" => "tools/list",
            "params" => %{}
          },
          mcp_session_id,
          session.session_id
        )

      ash_context = get_in(conn.private, [:ash, :context]) || %{}
      scope = ash_context[:spotter_mcp_scope]
      assert scope != nil
      assert scope.project_id == project.id
    end

    test "header takes priority over session_id query param", %{
      session: session,
      project: project
    } do
      {_body, mcp_session_id} = initialize()

      # Use both header and query param — header should win
      conn =
        Phoenix.ConnTest.build_conn()
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("x-spotter-project-dir", "test-mcp-project")
        |> Plug.Conn.put_req_header("mcp-session-id", mcp_session_id)

      conn =
        Phoenix.ConnTest.dispatch(
          conn,
          @endpoint,
          :post,
          "/api/mcp?session_id=#{session.session_id}",
          %{
            "jsonrpc" => "2.0",
            "id" => 201,
            "method" => "tools/list",
            "params" => %{}
          }
        )

      ash_context = get_in(conn.private, [:ash, :context]) || %{}
      scope = ash_context[:spotter_mcp_scope]
      assert scope != nil
      assert scope.project_id == project.id
    end

    test "invalid session_id falls back to recent session", %{project: project} do
      {_body, mcp_session_id} = initialize()

      {200, _body, conn} =
        mcp_post_with_session_id(
          %{
            "jsonrpc" => "2.0",
            "id" => 202,
            "method" => "tools/list",
            "params" => %{}
          },
          mcp_session_id,
          "nonexistent-session-id"
        )

      ash_context = get_in(conn.private, [:ash, :context]) || %{}
      scope = ash_context[:spotter_mcp_scope]
      assert scope != nil
      assert scope.project_id == project.id
    end
  end

  describe "tools/call" do
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

    for tool_name <- ["list_sessions", "list_hotspots", "list_retros", "rate_retro_item"] do
      @tool_name tool_name
      test "calling pruned tool #{@tool_name} returns error" do
        {_body, session_id} = initialize()

        {200, body, _conn} =
          mcp_post_with_project_dir(
            %{
              "jsonrpc" => "2.0",
              "id" => 50,
              "method" => "tools/call",
              "params" => %{
                "name" => @tool_name,
                "arguments" => %{}
              }
            },
            session_id,
            "test-mcp-project"
          )

        # AshAi returns tool errors as isError result or JSON-RPC error
        cond do
          body["result"] != nil ->
            assert body["result"]["isError"] == true

          body["error"] != nil ->
            assert is_binary(body["error"]["message"])
            assert body["error"]["code"] != nil
        end
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

    test "create_hotspot creates a hotspot and returns success", %{project: project} do
      commit = Ash.create!(Commit, %{commit_hash: "abc123def456"})

      {_body, session_id} = initialize()

      {200, body, _conn} =
        mcp_post_with_project_dir(
          %{
            "jsonrpc" => "2.0",
            "id" => 5,
            "method" => "tools/call",
            "params" => %{
              "name" => "create_hotspot",
              "arguments" => %{
                "input" => %{
                  "commit_id" => commit.id,
                  "relative_path" => "lib/example.ex",
                  "line_start" => 10,
                  "line_end" => 20,
                  "snippet" => "def foo, do: :bar",
                  "reason" => "Complex function needs refactoring",
                  "overall_score" => 75.0
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

      hotspot = Ash.read_first!(CommitHotspot)
      assert hotspot.relative_path == "lib/example.ex"
      assert hotspot.line_start == 10
      assert hotspot.line_end == 20
      assert hotspot.reason == "Complex function needs refactoring"
      assert hotspot.overall_score == 75.0
      assert hotspot.project_id == project.id
      assert hotspot.commit_id == commit.id
    end

    test "submit_retro creates a retro submission with items", %{
      session: session,
      project: project
    } do
      {_body, mcp_session_id} = initialize()

      {200, body, _conn} =
        mcp_post_with_project_dir(
          %{
            "jsonrpc" => "2.0",
            "id" => 6,
            "method" => "tools/call",
            "params" => %{
              "name" => "submit_retro",
              "arguments" => %{
                "input" => %{
                  "session_id" => session.session_id,
                  "summary" => "Good session overall",
                  "items" => [
                    %{
                      "category" => "effective_strategy",
                      "observation" => "Used TDD approach",
                      "explanation" => "Caught bugs early"
                    }
                  ]
                }
              }
            }
          },
          mcp_session_id,
          "test-mcp-project"
        )

      result = body["result"]
      assert result != nil, "Expected result but got: #{inspect(body)}"
      assert result["isError"] in [false, nil]

      submission = Ash.read_first!(RetroSubmission)
      assert submission.summary == "Good session overall"
      assert submission.project_id == project.id
      assert submission.session_id == session.id
    end
  end
end
