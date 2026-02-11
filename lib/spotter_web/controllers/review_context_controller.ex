defmodule SpotterWeb.ReviewContextController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Spotter.Services.ReviewContextBuilder
  alias Spotter.Services.ReviewTokenStore

  def show(conn, %{"token" => token}) do
    case ReviewTokenStore.consume(token) do
      {:ok, project_id} ->
        case ReviewContextBuilder.build(project_id) do
          {:ok, context} ->
            json(conn, %{ok: true, context: context})

          {:error, _} ->
            conn |> put_status(:not_found) |> json(%{error: "project not found"})
        end

      {:error, :invalid} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid or expired token"})
    end
  end
end
