defmodule SpotterWeb.HooksController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Spotter.Transcripts.FileSnapshot
  alias Spotter.Transcripts.Session

  require Ash.Query

  def file_snapshot(conn, %{"session_id" => session_id} = params)
      when is_binary(session_id) do
    with {:ok, session} <- find_session(session_id),
         {:ok, attrs} <- build_attrs(params, session),
         {:ok, _snapshot} <- Ash.create(FileSnapshot, attrs) do
      conn
      |> put_status(:created)
      |> json(%{ok: true})
    else
      {:error, :session_not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "session not found"})

      {:error, :invalid_params, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: reason})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(changeset)})
    end
  end

  def file_snapshot(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{error: "session_id is required"})
  end

  defp find_session(session_id) do
    case Session |> Ash.Query.filter(session_id == ^session_id) |> Ash.read_one() do
      {:ok, nil} -> {:error, :session_not_found}
      {:ok, session} -> {:ok, session}
      {:error, _} -> {:error, :session_not_found}
    end
  end

  defp build_attrs(params, session) do
    with {:ok, change_type} <- to_existing_atom(params["change_type"], "change_type"),
         {:ok, source} <- to_existing_atom(params["source"], "source"),
         {:ok, timestamp} <- parse_timestamp(params["timestamp"]) do
      {:ok,
       %{
         session_id: session.id,
         tool_use_id: params["tool_use_id"],
         file_path: params["file_path"],
         relative_path: params["relative_path"],
         content_before: params["content_before"],
         content_after: params["content_after"],
         change_type: change_type,
         source: source,
         timestamp: timestamp
       }}
    end
  end

  defp to_existing_atom(value, field) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, :invalid_params, "invalid #{field}: #{value}"}
  end

  defp to_existing_atom(nil, field), do: {:error, :invalid_params, "#{field} is required"}

  defp parse_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> {:ok, DateTime.utc_now()}
    end
  end

  defp parse_timestamp(_), do: {:ok, DateTime.utc_now()}
end
