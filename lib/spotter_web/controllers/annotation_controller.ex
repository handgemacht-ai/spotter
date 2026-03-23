defmodule SpotterWeb.AnnotationController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  require Ash.Query
  require SpotterWeb.OtelTraceHelpers

  alias Spotter.ImageStore
  alias Spotter.Transcripts.Annotation
  alias Spotter.Transcripts.Project
  alias SpotterWeb.OtelTraceHelpers

  @max_image_bytes 5 * 1024 * 1024

  def index(conn, params) do
    OtelTraceHelpers.with_span "spotter.web.annotation.index", %{} do
      case resolve_project(params) do
        {:ok, project_id} ->
          args = %{project_id: project_id}
          args = if params["bead_id"], do: Map.put(args, :bead_id, params["bead_id"]), else: args

          annotations =
            Annotation
            |> Ash.Query.for_read(:rest_list, args)
            |> Ash.Query.load(:has_image)
            |> Ash.Query.sort(inserted_at: :desc)
            |> Ash.read!()

          conn
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(Enum.map(annotations, &serialize_annotation/1))

        {:error, :project_not_found} ->
          OtelTraceHelpers.set_error("project_not_found", %{
            "error.source" => "annotation_controller"
          })

          conn
          |> put_status(:not_found)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "project not found"})
      end
    end
  end

  def create(conn, params) do
    OtelTraceHelpers.with_span "spotter.web.annotation.create", %{
      "spotter.annotation.source" => params["source"] || "unknown"
    } do
      with {:ok, project_id} <- resolve_project(params),
           {:ok, annotation} <- Ash.create(Annotation, build_attrs(params, project_id)) do
        conn
        |> put_status(:created)
        |> OtelTraceHelpers.put_trace_response_header()
        |> json(%{id: annotation.id})
      else
        {:error, :project_not_found} ->
          OtelTraceHelpers.set_error("project_not_found", %{
            "error.source" => "annotation_controller"
          })

          conn
          |> put_status(:not_found)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "project not found"})

        {:error, %Ash.Error.Invalid{} = err} ->
          OtelTraceHelpers.set_error("validation_error", %{
            "error.source" => "annotation_controller",
            "error.message" => Exception.message(err)
          })

          conn
          |> put_status(:unprocessable_entity)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: format_ash_error(err)})

        {:error, reason} ->
          OtelTraceHelpers.set_error("create_failed", %{
            "error.source" => "annotation_controller",
            "error.message" => inspect(reason)
          })

          conn
          |> put_status(:unprocessable_entity)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "annotation creation failed"})
      end
    end
  end

  def attach_image(conn, %{"id" => annotation_id}) do
    OtelTraceHelpers.with_span "spotter.web.annotation.attach_image", %{
      "spotter.annotation.id" => annotation_id
    } do
      with :ok <- validate_image_content_type(conn),
           {:ok, annotation} <- fetch_annotation(annotation_id),
           {:ok, body} <- read_image_body(conn),
           {:ok, ref} <- ImageStore.store(body, annotation.id),
           {:ok, _updated} <- Ash.update(annotation, %{image_ref: ref}) do
        conn
        |> OtelTraceHelpers.put_trace_response_header()
        |> json(%{ok: true})
      else
        {:error, :not_found} ->
          OtelTraceHelpers.set_error("annotation_not_found", %{
            "error.source" => "annotation_controller"
          })

          conn
          |> put_status(:not_found)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "annotation not found"})

        {:error, tag} when tag in [:image_too_large, :too_large] ->
          OtelTraceHelpers.set_error("image_too_large", %{
            "error.source" => "annotation_controller",
            "error.max_bytes" => @max_image_bytes
          })

          conn
          |> put_status(413)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "image exceeds 5MB limit"})

        {:error, :empty_body} ->
          OtelTraceHelpers.set_error("empty_body", %{
            "error.source" => "annotation_controller"
          })

          conn
          |> put_status(:bad_request)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "request body is empty"})

        {:error, :unsupported_content_type} ->
          OtelTraceHelpers.set_error("unsupported_content_type", %{
            "error.source" => "annotation_controller"
          })

          conn
          |> put_status(:unsupported_media_type)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "content-type must be image/png or application/octet-stream"})

        {:error, reason} ->
          OtelTraceHelpers.set_error("attach_image_failed", %{
            "error.source" => "annotation_controller",
            "error.message" => inspect(reason)
          })

          conn
          |> put_status(:unprocessable_entity)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "image attachment failed"})
      end
    end
  end

  def show_image(conn, %{"id" => annotation_id}) do
    OtelTraceHelpers.with_span "spotter.web.annotation.show_image", %{
      "spotter.annotation.id" => annotation_id
    } do
      with {:ok, annotation} <- fetch_annotation(annotation_id),
           {:ok, image_ref} <- require_image_ref(annotation),
           {:ok, image_binary} <- ImageStore.fetch(image_ref) do
        conn
        |> put_resp_content_type("image/png")
        |> put_resp_header("cache-control", "private, max-age=3600")
        |> OtelTraceHelpers.put_trace_response_header()
        |> send_resp(200, image_binary)
      else
        {:error, :not_found} ->
          OtelTraceHelpers.set_error("not_found", %{
            "error.source" => "annotation_controller"
          })

          conn
          |> put_status(:not_found)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "not found"})

        {:error, :no_image} ->
          OtelTraceHelpers.set_error("no_image", %{
            "error.source" => "annotation_controller"
          })

          conn
          |> put_status(:not_found)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "no image attached"})

        {:error, reason} ->
          OtelTraceHelpers.set_error("show_image_failed", %{
            "error.source" => "annotation_controller",
            "error.message" => inspect(reason)
          })

          conn
          |> put_status(:internal_server_error)
          |> OtelTraceHelpers.put_trace_response_header()
          |> json(%{error: "image retrieval failed"})
      end
    end
  end

  # --- Private helpers ---

  defp resolve_project(%{"project_id" => project_id}) when is_binary(project_id) do
    case Ash.get(Project, project_id) do
      {:ok, project} -> {:ok, project.id}
      {:error, _} -> {:error, :project_not_found}
    end
  end

  defp resolve_project(%{"project_name" => name}) when is_binary(name) do
    Project
    |> Ash.Query.filter(name == ^name)
    |> Ash.read_one()
    |> case do
      {:ok, %Project{} = project} -> {:ok, project.id}
      {:ok, nil} -> {:error, :project_not_found}
      {:error, _} -> {:error, :project_not_found}
    end
  end

  defp resolve_project(_params), do: {:error, :project_not_found}

  defp build_attrs(params, project_id) do
    attrs = %{
      source: parse_source(params["source"]),
      comment: params["comment"] || "",
      selected_text: params["selected_text"] || "",
      project_id: project_id,
      metadata: params["metadata"] || %{}
    }

    if params["bead_id"], do: Map.put(attrs, :bead_id, params["bead_id"]), else: attrs
  end

  defp parse_source("product_feedback"), do: :product_feedback
  defp parse_source("plan"), do: :plan
  defp parse_source("file"), do: :file
  defp parse_source("terminal"), do: :terminal
  defp parse_source("transcript"), do: :transcript
  defp parse_source("commit_message"), do: :commit_message
  defp parse_source("code"), do: :code
  defp parse_source("prompt_pattern"), do: :prompt_pattern
  defp parse_source(_), do: :product_feedback

  @allowed_image_types ["image/png", "application/octet-stream"]

  defp validate_image_content_type(conn) do
    content_type =
      Plug.Conn.get_req_header(conn, "content-type")
      |> List.first("")
      |> String.split(";")
      |> List.first()
      |> String.trim()

    if content_type in @allowed_image_types, do: :ok, else: {:error, :unsupported_content_type}
  end

  defp require_image_ref(%{image_ref: ref}) when is_binary(ref), do: {:ok, ref}
  defp require_image_ref(_), do: {:error, :no_image}

  defp fetch_annotation(id) do
    case Ash.get(Annotation, id) do
      {:ok, annotation} -> {:ok, annotation}
      {:error, _} -> {:error, :not_found}
    end
  end

  defp read_image_body(conn) do
    case Plug.Conn.read_body(conn, length: @max_image_bytes) do
      {:ok, body, _conn} when byte_size(body) > 0 ->
        {:ok, body}

      {:more, _partial, _conn} ->
        {:error, :image_too_large}

      _ ->
        {:error, :empty_body}
    end
  end

  defp format_ash_error(%Ash.Error.Invalid{errors: errors}) do
    Enum.map_join(errors, "; ", &Exception.message/1)
  end

  defp format_ash_error(err), do: Exception.message(err)

  defp serialize_annotation(ann) do
    %{
      id: ann.id,
      comment: ann.comment,
      selected_text: ann.selected_text,
      source: ann.source,
      bead_id: ann.bead_id,
      state: ann.state,
      has_image: ann.has_image,
      metadata: ann.metadata,
      inserted_at: ann.inserted_at
    }
  end
end
