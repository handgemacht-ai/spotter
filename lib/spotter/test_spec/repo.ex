defmodule Spotter.TestSpec.Repo do
  @moduledoc """
  Ecto repo for the Dolt SQL-server backing the test specification store.
  """

  use Ecto.Repo, otp_app: :spotter, adapter: Ecto.Adapters.MyXQL
end
