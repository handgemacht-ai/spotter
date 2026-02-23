defmodule SpotterWeb.ImportModalTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox

  @endpoint SpotterWeb.Endpoint

  setup do
    pid = Sandbox.start_owner!(Spotter.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    :ok
  end

  describe "Import button on dashboard" do
    test "dashboard renders an Import button" do
      {:ok, _view, html} = live(build_conn(), "/")

      assert html =~ ~s(data-testid="import-button")
      assert html =~ "Import"
    end
  end
end
