defmodule SpotterWeb.ErrorRenderingTest do
  use ExUnit.Case, async: true

  alias Phoenix.HTML.Safe

  @endpoint SpotterWeb.Endpoint

  @tag :slow
  @tag timeout: 5_000
  test "unknown html route renders 404 page" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("accept", "text/html")
      |> Phoenix.ConnTest.dispatch(@endpoint, :get, "/__missing__")

    assert conn.status == 404
    assert conn.resp_body =~ "Page not found"
  end

  @tag :slow
  @tag timeout: 5_000
  test "unknown json route renders structured 404 response" do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("accept", "application/json")
      |> Phoenix.ConnTest.dispatch(@endpoint, :get, "/__missing__")

    assert conn.status == 404
    assert %{"errors" => %{"detail" => "Not Found"}} = Jason.decode!(conn.resp_body)
  end

  test "500 html page copy is present" do
    body =
      SpotterWeb.ErrorHTML.render("500.html", %{})
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert body =~ "Internal server error"
  end

  test "endpoint config uses ErrorHTML and ErrorJSON for render_errors" do
    endpoint_config = Application.get_env(:spotter, SpotterWeb.Endpoint, [])

    assert endpoint_config[:render_errors] == [
             formats: [html: SpotterWeb.ErrorHTML, json: SpotterWeb.ErrorJSON],
             layout: false
           ]
  end
end
