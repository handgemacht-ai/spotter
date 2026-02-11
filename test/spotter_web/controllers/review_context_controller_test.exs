defmodule SpotterWeb.ReviewContextControllerTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo
  alias Spotter.Services.ReviewTokenStore
  alias Spotter.Transcripts.{Annotation, Project, Session}

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  defp create_project_with_annotation do
    project =
      Ash.create!(Project, %{
        name: "api-test-#{System.unique_integer([:positive])}",
        pattern: "^test"
      })

    session =
      Ash.create!(Session, %{
        session_id: Ash.UUID.generate(),
        transcript_dir: "test-dir",
        project_id: project.id
      })

    Ash.create!(Annotation, %{
      session_id: session.id,
      selected_text: "review this",
      comment: "important"
    })

    project
  end

  test "returns context for valid token" do
    project = create_project_with_annotation()
    token = ReviewTokenStore.mint(project.id)

    conn = build_conn() |> get("/api/review-context/#{token}")

    assert json_response(conn, 200)["ok"] == true
    assert json_response(conn, 200)["context"] =~ "Project Review: #{project.name}"
    assert json_response(conn, 200)["context"] =~ "review this"
  end

  test "token is consumed after first use" do
    project = create_project_with_annotation()
    token = ReviewTokenStore.mint(project.id)

    conn1 = build_conn() |> get("/api/review-context/#{token}")
    assert json_response(conn1, 200)["ok"] == true

    conn2 = build_conn() |> get("/api/review-context/#{token}")
    assert json_response(conn2, 401)["error"] =~ "invalid or expired"
  end

  test "rejects invalid token" do
    conn = build_conn() |> get("/api/review-context/bogus-token")

    assert json_response(conn, 401)["error"] =~ "invalid or expired"
  end

  test "rejects expired token" do
    project = create_project_with_annotation()
    token = ReviewTokenStore.mint(project.id, 0)

    Process.sleep(10)

    conn = build_conn() |> get("/api/review-context/#{token}")

    assert json_response(conn, 401)["error"] =~ "invalid or expired"
  end
end
