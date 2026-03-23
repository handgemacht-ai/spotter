defmodule SpotterWeb.AnnotationControllerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Transcripts.{Annotation, Project}

  @endpoint SpotterWeb.Endpoint

  setup do
    Sandbox.checkout(Repo)

    project = Ash.create!(Project, %{name: "test-annotations", pattern: "^test-ann"})

    %{project: project}
  end

  defp post_annotation(params, headers \\ []) do
    conn =
      Enum.reduce(headers, Phoenix.ConnTest.build_conn(), fn {k, v}, conn ->
        Plug.Conn.put_req_header(conn, k, v)
      end)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Phoenix.ConnTest.dispatch(@endpoint, :post, "/api/annotations", params)

    {conn.status, Jason.decode!(conn.resp_body), conn}
  end

  defp post_image(annotation_id, body, headers \\ []) do
    conn =
      Enum.reduce(headers, Phoenix.ConnTest.build_conn(), fn {k, v}, conn ->
        Plug.Conn.put_req_header(conn, k, v)
      end)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> Phoenix.ConnTest.dispatch(
        @endpoint,
        :post,
        "/api/annotations/#{annotation_id}/image",
        body
      )

    {conn.status, Jason.decode!(conn.resp_body), conn}
  end

  @valid_traceparent "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"

  describe "POST /api/annotations" do
    test "creates annotation with valid params and returns 201", %{project: project} do
      params = %{
        "selected_text" => "some code to review",
        "comment" => "This needs refactoring",
        "source" => "file",
        "project_id" => project.id
      }

      {status, body, _conn} = post_annotation(params)

      assert status == 201
      assert is_binary(body["id"])

      annotations = Ash.read!(Annotation)
      assert length(annotations) == 1
      assert hd(annotations).comment == "This needs refactoring"
      assert hd(annotations).selected_text == "some code to review"
      assert hd(annotations).source == :file
      assert to_string(hd(annotations).project_id) == to_string(project.id)
    end

    test "returns 404 when project_id does not exist" do
      params = %{
        "selected_text" => "text",
        "comment" => "comment",
        "source" => "file",
        "project_id" => Ash.UUID.generate()
      }

      {status, body, _conn} = post_annotation(params)

      assert status == 404
      assert body["error"] =~ "project"
    end

    test "returns 404 when project_id is missing" do
      params = %{
        "selected_text" => "text",
        "comment" => "comment",
        "source" => "file"
      }

      {status, body, _conn} = post_annotation(params)

      assert status == 404
      assert body["error"] =~ "project"
    end

    test "returns 422 when required fields are missing", %{project: project} do
      params = %{
        "source" => "file",
        "project_id" => project.id
      }

      {status, body, _conn} = post_annotation(params)

      assert status == 422
      assert is_binary(body["error"])
    end

    test "resolves project by name", %{project: project} do
      params = %{
        "selected_text" => "text",
        "comment" => "by name",
        "source" => "plan",
        "project_name" => project.name
      }

      {status, body, _conn} = post_annotation(params)

      assert status == 201
      assert is_binary(body["id"])

      annotation = Ash.read!(Annotation) |> hd()
      assert to_string(annotation.project_id) == to_string(project.id)
    end

    test "includes x-spotter-trace-id in response headers", %{project: project} do
      params = %{
        "selected_text" => "text",
        "comment" => "trace test",
        "source" => "file",
        "project_id" => project.id
      }

      {_status, _body, conn} = post_annotation(params, [{"traceparent", @valid_traceparent}])

      trace_id = conn |> Plug.Conn.get_resp_header("x-spotter-trace-id") |> List.first()
      assert trace_id != nil
    end
  end

  describe "POST /api/annotations/:id/image" do
    test "attaches image to existing annotation", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          selected_text: "img test",
          comment: "attach image",
          source: :file,
          project_id: project.id
        })

      png_body = :crypto.strong_rand_bytes(128)

      {status, body, _conn} = post_image(annotation.id, png_body)

      assert status == 200
      assert body["ok"] == true

      updated = Ash.get!(Annotation, annotation.id)
      assert updated.image_ref != nil
    end

    test "returns 404 for non-existent annotation" do
      {status, body, _conn} = post_image(Ash.UUID.generate(), <<1, 2, 3>>)

      assert status == 404
      assert body["error"] =~ "annotation not found"
    end

    test "returns 413 when image exceeds 5MB", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          selected_text: "big img",
          comment: "too large",
          source: :file,
          project_id: project.id
        })

      large_body = :binary.copy(<<0>>, 5 * 1024 * 1024 + 1)

      {status, body, _conn} = post_image(annotation.id, large_body)

      assert status == 413
      assert body["error"] =~ "5MB"
    end

    test "includes x-spotter-trace-id in response headers", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          selected_text: "trace img",
          comment: "trace",
          source: :file,
          project_id: project.id
        })

      {_status, _body, conn} =
        post_image(annotation.id, <<1, 2, 3>>, [{"traceparent", @valid_traceparent}])

      trace_id = conn |> Plug.Conn.get_resp_header("x-spotter-trace-id") |> List.first()
      assert trace_id != nil
    end
  end

  defp delete_annotation(id, headers \\ []) do
    conn =
      Enum.reduce(headers, Phoenix.ConnTest.build_conn(), fn {k, v}, conn ->
        Plug.Conn.put_req_header(conn, k, v)
      end)
      |> Phoenix.ConnTest.dispatch(@endpoint, :delete, "/api/annotations/#{id}")

    {conn.status, Jason.decode!(conn.resp_body), conn}
  end

  describe "DELETE /api/annotations/:id" do
    test "deletes annotation and returns ok", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          selected_text: "to delete",
          comment: "delete me",
          source: :file,
          project_id: project.id
        })

      {status, body, _conn} = delete_annotation(annotation.id)

      assert status == 200
      assert body["ok"] == true

      assert {:error, _} = Ash.get(Annotation, annotation.id)
    end

    test "deletes annotation with image and cleans up image", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          selected_text: "img delete",
          comment: "has image",
          source: :file,
          project_id: project.id
        })

      png_body = :crypto.strong_rand_bytes(128)
      {200, _, _} = post_image(annotation.id, png_body)

      updated = Ash.get!(Annotation, annotation.id)
      assert updated.image_ref != nil

      {status, body, _conn} = delete_annotation(annotation.id)

      assert status == 200
      assert body["ok"] == true

      assert {:error, _} = Ash.get(Annotation, annotation.id)
      assert {:error, _} = Spotter.ImageStore.fetch(updated.image_ref)
    end

    test "returns 404 for non-existent annotation" do
      {status, body, _conn} = delete_annotation(Ash.UUID.generate())

      assert status == 404
      assert body["error"] =~ "annotation not found"
    end

    test "includes x-spotter-trace-id in response headers", %{project: project} do
      annotation =
        Ash.create!(Annotation, %{
          selected_text: "trace delete",
          comment: "trace",
          source: :file,
          project_id: project.id
        })

      {_status, _body, conn} =
        delete_annotation(annotation.id, [{"traceparent", @valid_traceparent}])

      trace_id = conn |> Plug.Conn.get_resp_header("x-spotter-trace-id") |> List.first()
      assert trace_id != nil
    end
  end
end
