defmodule Spotter.Observability.AgentRunInput do
  @moduledoc """
  Deterministic extraction helpers for normalizing agent runner input maps.

  Oban job args arrive with string keys, while internal callers use atom keys.
  These helpers unify both formats into a consistent atom-key map.
  """

  @doc """
  Fetches a required value from input, checking atom key first, then string key.

  Returns `{:ok, value}` or `{:error, {:missing_key, key}}`.
  Empty strings for binary values are treated as missing.
  """
  @spec fetch_required(map(), atom()) :: {:ok, term()} | {:error, {:missing_key, atom()}}
  def fetch_required(input, key) when is_atom(key) do
    case Map.get(input, key) do
      nil ->
        case Map.get(input, Atom.to_string(key)) do
          nil -> {:error, {:missing_key, key}}
          "" -> {:error, {:missing_key, key}}
          value -> {:ok, value}
        end

      "" ->
        {:error, {:missing_key, key}}

      value ->
        {:ok, value}
    end
  end

  @doc """
  Gets an optional value from input, checking atom key first, then string key.

  Returns the value or the default if not found.
  """
  @spec get_optional(map(), atom(), term()) :: term()
  def get_optional(input, key, default \\ nil) when is_atom(key) do
    case Map.get(input, key) do
      nil -> Map.get(input, Atom.to_string(key), default)
      value -> value
    end
  end

  @doc """
  Normalizes an input map by extracting required and optional keys into an atom-key map.

  Returns `{:ok, normalized_map}` or `{:error, {:missing_keys, [atom()]}}`.
  """
  @spec normalize(map(), [atom()], [atom() | {atom(), term()}]) ::
          {:ok, map()} | {:error, {:missing_keys, [atom()]}}
  def normalize(input, required_keys, optional_keys \\ []) do
    {required_vals, missing} =
      Enum.reduce(required_keys, {%{}, []}, fn key, {acc, miss} ->
        case fetch_required(input, key) do
          {:ok, val} -> {Map.put(acc, key, val), miss}
          {:error, _} -> {acc, [key | miss]}
        end
      end)

    case missing do
      [] ->
        optional_vals =
          Enum.reduce(optional_keys, %{}, fn
            {key, default}, acc -> Map.put(acc, key, get_optional(input, key, default))
            key, acc -> Map.put(acc, key, get_optional(input, key))
          end)

        {:ok, Map.merge(required_vals, optional_vals)}

      keys ->
        {:error, {:missing_keys, Enum.reverse(keys)}}
    end
  end
end
