defmodule SpotterWeb.ReviewsRedirectControllerTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Spotter.Repo

  @endpoint SpotterWeb.Endpoint

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
  end

  test "redirects to /reviews with project_id param" do
    project_id = Ash.UUID.generate()
    conn = build_conn() |> get("/projects/#{project_id}/review")

    assert redirected_to(conn) == "/reviews?project_id=#{project_id}"
  end

  test "redirects for arbitrary project_id values without error" do
    conn = build_conn() |> get("/projects/not-a-uuid/review")

    assert redirected_to(conn) == "/reviews?project_id=not-a-uuid"
  end
end
