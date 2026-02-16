defmodule Spotter.Search.Result do
  @moduledoc """
  A single search result returned by `Spotter.Search.search/2`.
  """

  @type t :: %__MODULE__{
          kind: String.t(),
          project_id: String.t(),
          external_id: String.t(),
          title: String.t(),
          subtitle: String.t() | nil,
          url: String.t(),
          score: float()
        }

  @enforce_keys [:kind, :project_id, :external_id, :title, :url, :score]
  defstruct [:kind, :project_id, :external_id, :title, :subtitle, :url, :score]
end
