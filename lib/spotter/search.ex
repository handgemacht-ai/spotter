defmodule Spotter.Search do
  @moduledoc """
  Public facade for the unified search surface.

  Delegates to `Spotter.Search.Query` for FTS5 / LIKE-fallback queries
  against the `search_documents` table.
  """

  alias Spotter.Search.Query

  @doc """
  Searches the unified index. Returns `[Spotter.Search.Result.t()]`, never raises.

  ## Options

    * `:project_id` - optional UUID to scope results to a single project
    * `:limit` - max results, default 20, clamped to 1..50
  """
  @spec search(String.t(), keyword()) :: [Spotter.Search.Result.t()]
  defdelegate search(q, opts \\ []), to: Query
end
