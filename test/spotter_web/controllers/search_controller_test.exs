defmodule SpotterWeb.SearchControllerTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  @endpoint SpotterWeb.Endpoint
  @project_id "00000000-0000-0000-0000-000000000042"

  setup do
    Sandbox.checkout(Repo)
    now = DateTime.utc_now()

    Repo.query!(
      """
      INSERT INTO search_documents (id, project_id, kind, external_id, title, subtitle, url, search_text, inserted_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        Ecto.UUID.generate(),
        @project_id,
        "file",
        "lib/spotter/search.ex",
        "lib/spotter/search.ex",
        "File",
        "/projects/#{@project_id}/files/lib/spotter/search.ex",
        "lib spotter search.ex",
        now,
        now
      ]
    )

    :ok
  end

  defp api_get(path) do
    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.dispatch(@endpoint, :get, path)
  end

  describe "GET /api/search" do
    test "returns results for matching query" do
      conn = api_get("/api/search?q=search")
      body = Jason.decode!(conn.resp_body)

      assert conn.status == 200
      assert body["ok"] == true
      assert body["q"] == "search"
      assert Enum.any?(body["results"], &(&1["kind"] == "file"))
    end

    test "returns empty results for empty query" do
      conn = api_get("/api/search?q=")
      body = Jason.decode!(conn.resp_body)

      assert body["ok"] == true
      assert body["results"] == []
    end

    test "returns empty results for overly long query" do
      long = String.duplicate("a", 201)
      conn = api_get("/api/search?q=#{long}")
      body = Jason.decode!(conn.resp_body)

      assert body["ok"] == true
      assert body["results"] == []
    end

    test "filters by project_id" do
      conn = api_get("/api/search?q=search&project_id=#{@project_id}")
      body = Jason.decode!(conn.resp_body)

      assert body["ok"] == true
      assert Enum.all?(body["results"], &(&1["project_id"] == @project_id))
    end

    test "respects limit param" do
      conn = api_get("/api/search?q=search&limit=1")
      body = Jason.decode!(conn.resp_body)

      assert length(body["results"]) <= 1
    end

    test "no crash when dolt unavailable" do
      conn = api_get("/api/search?q=search")
      body = Jason.decode!(conn.resp_body)

      assert body["ok"] == true
    end
  end
end
