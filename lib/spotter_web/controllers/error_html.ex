defmodule SpotterWeb.ErrorHTML do
  @moduledoc """
  Renders error pages for HTTP requests.
  """
  use Phoenix.Component

  def render("404.html", assigns) do
    ~H"""
    <div style="display: flex; justify-content: center; align-items: center; height: 100vh; background: #1a1a2e; color: #e0e0e0; font-family: monospace;">
      <div style="text-align: center;">
        <h1 style="font-size: 3rem; margin: 0; color: #64b5f6;">404</h1>
        <p>Page not found</p>
        <a href="/" style="color: #64b5f6;">Back to home</a>
      </div>
    </div>
    """
  end

  def render("500.html", assigns) do
    ~H"""
    <div style="display: flex; justify-content: center; align-items: center; height: 100vh; background: #1a1a2e; color: #e0e0e0; font-family: monospace;">
      <div style="text-align: center;">
        <h1 style="font-size: 3rem; margin: 0; color: #c0392b;">500</h1>
        <p>Internal server error</p>
        <a href="/" style="color: #64b5f6;">Back to home</a>
      </div>
    </div>
    """
  end

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
