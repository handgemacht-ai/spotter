defmodule Spotter.Transcripts.AnnotationMcpToolsTest do
  use Spotter.DataCase, async: false

  require Ash.Query

  alias Spotter.Transcripts.{Annotation, Project, Session}
  alias Spotter.ImageStore

  @endpoint SpotterWeb.Endpoint

  setup do
    project = Ash.create!(Project, %{name: "test-mcp-image", pattern: "^test"})

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

    %{project: project, session: session}
  end

  # -- MCP helpers (same pattern as spotter_mcp_plug_test.exs) --

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

  defp call_tool(tool_name, arguments, mcp_session_id, project_dir) do
    mcp_post_with_project_dir(
      %{
        "jsonrpc" => "2.0",
        "id" => System.unique_integer([:positive]),
        "method" => "tools/call",
        "params" => %{
          "name" => tool_name,
          "arguments" => arguments
        }
      },
      mcp_session_id,
      project_dir
    )
  end

  # -- Test 1: has_image calculation returns false when image_ref is nil --

  describe "has_image calculation" do
    test "returns false when image_ref is nil", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          source: :product_feedback,
          selected_text: "no image here",
          comment: "plain feedback",
          project_id: project.id
        })

      loaded = Ash.load!(annotation, :has_image)
      assert loaded.has_image == false
    end

    # -- Test 2: has_image calculation returns true when image_ref is set --

    test "returns true when image_ref is set", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          source: :product_feedback,
          selected_text: "has image",
          comment: "feedback with screenshot",
          project_id: project.id,
          image_ref: "img-ref-123"
        })

      loaded = Ash.load!(annotation, :has_image)
      assert loaded.has_image == true
    end
  end

  # -- Test 3: list_review_annotations MCP tool response includes has_image field --

  describe "list_review_annotations includes has_image" do
    test "response contains has_image field for each annotation", %{
      session: session,
      project: project
    } do
      Ash.create!(Annotation, %{
        session_id: session.id,
        source: :transcript,
        selected_text: "check this",
        comment: "review with no image",
        purpose: :review,
        state: :open,
        project_id: project.id
      })

      Ash.create!(Annotation, %{
        session_id: session.id,
        source: :transcript,
        selected_text: "check that",
        comment: "review with image",
        purpose: :review,
        state: :open,
        project_id: project.id,
        image_ref: "img-ref-456"
      })

      {_body, mcp_session_id} = initialize()

      {200, body, _conn} =
        call_tool("list_review_annotations", %{}, mcp_session_id, "test-mcp-image-project")

      [content | _] = body["result"]["content"]
      annotations = Jason.decode!(content["text"])

      assert length(annotations) == 2

      without_image = Enum.find(annotations, &(&1["comment"] == "review with no image"))
      with_image = Enum.find(annotations, &(&1["comment"] == "review with image"))

      assert without_image["has_image"] == false
      assert with_image["has_image"] == true
    end
  end

  # -- Test 4: get_annotation_image returns base64 PNG for annotation with image --

  describe "get_annotation_image MCP tool" do
    test "returns base64 PNG for annotation with stored image", %{
      session: session,
      project: project
    } do
      png_binary = <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 1>>

      annotation =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :transcript,
          selected_text: "screenshot area",
          comment: "has screenshot",
          purpose: :review,
          state: :open,
          project_id: project.id
        })

      {:ok, ref} = ImageStore.store(png_binary, annotation.id)
      Ash.update!(annotation, %{image_ref: ref})

      {_body, mcp_session_id} = initialize()

      {200, body, _conn} =
        call_tool(
          "get_annotation_image",
          %{"id" => annotation.id},
          mcp_session_id,
          "test-mcp-image-project"
        )

      result = body["result"]
      refute result["isError"], "Expected success but got error: #{inspect(result)}"

      [content | _] = result["content"]
      assert content["type"] == "image"
      assert content["mimeType"] == "image/png"

      decoded = Base.decode64!(content["data"])
      assert decoded == png_binary
    end

    # -- Test 5: get_annotation_image returns error for annotation without image --

    test "returns error for annotation without image", %{
      session: session,
      project: project
    } do
      annotation =
        Ash.create!(Annotation, %{
          session_id: session.id,
          source: :transcript,
          selected_text: "no screenshot",
          comment: "no image attached",
          purpose: :review,
          state: :open,
          project_id: project.id
        })

      {_body, mcp_session_id} = initialize()

      {200, body, _conn} =
        call_tool(
          "get_annotation_image",
          %{"id" => annotation.id},
          mcp_session_id,
          "test-mcp-image-project"
        )

      result = body["result"]
      assert result["isError"] == true

      [content | _] = result["content"]
      text = content["text"]
      assert text =~ ~r/no image|not found|image_ref/i
    end
  end

  # -- Test 6: Project scoping — MCP tools respect project context --

  describe "project scoping" do
    test "get_annotation_image rejects annotation from different project", %{
      session: session
    } do
      other_project = Ash.create!(Project, %{name: "other-project", pattern: "^other"})

      other_session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "other-dir",
          project_id: other_project.id
        })

      png_binary = <<137, 80, 78, 71, 13, 10, 26, 10>>

      annotation =
        Ash.create!(Annotation, %{
          session_id: other_session.id,
          source: :transcript,
          selected_text: "other project code",
          comment: "cross-project annotation",
          purpose: :review,
          state: :open,
          project_id: other_project.id
        })

      {:ok, ref} = ImageStore.store(png_binary, annotation.id)
      Ash.update!(annotation, %{image_ref: ref})

      {_body, mcp_session_id} = initialize()

      # Call with the FIRST project's dir — should not return other project's annotation image
      {200, body, _conn} =
        call_tool(
          "get_annotation_image",
          %{"id" => annotation.id},
          mcp_session_id,
          "test-mcp-image-project"
        )

      result = body["result"]
      assert result["isError"] == true

      [content | _] = result["content"]
      text = content["text"]
      assert text =~ ~r/project|scope|not found|unauthorized/i
    end

    test "list_review_annotations only returns annotations for scoped project", %{
      session: session,
      project: project
    } do
      other_project = Ash.create!(Project, %{name: "other-list-project", pattern: "^otherlist"})

      other_session =
        Ash.create!(Session, %{
          session_id: Ash.UUID.generate(),
          transcript_dir: "other-list-dir",
          project_id: other_project.id
        })

      Ash.create!(Annotation, %{
        session_id: session.id,
        source: :transcript,
        selected_text: "my project annotation",
        comment: "belongs to test-mcp-image",
        purpose: :review,
        state: :open,
        project_id: project.id
      })

      Ash.create!(Annotation, %{
        session_id: other_session.id,
        source: :transcript,
        selected_text: "other project annotation",
        comment: "belongs to other-list-project",
        purpose: :review,
        state: :open,
        project_id: other_project.id
      })

      {_body, mcp_session_id} = initialize()

      {200, body, _conn} =
        call_tool("list_review_annotations", %{}, mcp_session_id, "test-mcp-image-project")

      [content | _] = body["result"]["content"]
      annotations = Jason.decode!(content["text"])

      # Verify scoping: only our project's annotation is returned
      assert length(annotations) == 1
      [annotation] = annotations
      assert annotation["comment"] == "belongs to test-mcp-image"
    end
  end
end
