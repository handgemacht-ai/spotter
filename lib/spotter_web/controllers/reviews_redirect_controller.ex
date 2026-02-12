defmodule SpotterWeb.ReviewsRedirectController do
  use Phoenix.Controller, formats: [:html]

  def show(conn, %{"project_id" => project_id}) do
    redirect(conn, to: "/reviews?project_id=#{project_id}")
  end
end
