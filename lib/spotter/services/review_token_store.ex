defmodule Spotter.Services.ReviewTokenStore do
  @moduledoc false
  use GenServer

  @table __MODULE__
  @default_ttl_seconds 120

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Mints a new one-time token for a project review context.
  Returns the token string.
  """
  def mint(project_id, ttl_seconds \\ @default_ttl_seconds) do
    token = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    expires_at = System.monotonic_time(:second) + ttl_seconds
    :ets.insert(@table, {token, project_id, expires_at})
    token
  end

  @doc """
  Consumes a token if it exists and has not expired.
  Returns `{:ok, project_id}` or `{:error, :invalid}`.
  """
  def consume(token) do
    now = System.monotonic_time(:second)

    case :ets.lookup(@table, token) do
      [{^token, project_id, expires_at}] when expires_at > now ->
        :ets.delete(@table, token)
        {:ok, project_id}

      [{^token, _project_id, _expires_at}] ->
        :ets.delete(@table, token)
        {:error, :invalid}

      [] ->
        {:error, :invalid}
    end
  end

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{}}
  end
end
