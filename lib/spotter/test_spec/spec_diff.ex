defmodule Spotter.TestSpec.SpecDiff do
  @moduledoc """
  Pure semantic diff engine for test specification lists.

  Compares two flat lists of test maps keyed by `test_key` and produces
  a structured diff with added, removed, and changed entries.
  """

  @semantic_fields ~w(framework relative_path describe_path test_name line_start line_end given when then confidence metadata)a

  @doc """
  Computes a semantic diff between two test lists.

  Identity key: `test_key`

  Returns a map with `:added`, `:removed`, and `:changed` lists.
  """
  @spec diff([map()], [map()]) :: map()
  def diff(from_tests, to_tests) do
    from_index = Map.new(from_tests, &{&1.test_key, &1})
    to_index = Map.new(to_tests, &{&1.test_key, &1})

    from_keys = MapSet.new(Map.keys(from_index))
    to_keys = MapSet.new(Map.keys(to_index))

    added =
      to_keys
      |> MapSet.difference(from_keys)
      |> Enum.map(&Map.get(to_index, &1))
      |> Enum.sort_by(&{&1.relative_path, &1.test_key})

    removed =
      from_keys
      |> MapSet.difference(to_keys)
      |> Enum.map(&Map.get(from_index, &1))
      |> Enum.sort_by(&{&1.relative_path, &1.test_key})

    changed =
      from_keys
      |> MapSet.intersection(to_keys)
      |> Enum.reduce([], fn key, acc ->
        from_entry = Map.get(from_index, key)
        to_entry = Map.get(to_index, key)

        changed_fields =
          Enum.filter(@semantic_fields, fn field ->
            Map.get(from_entry, field) != Map.get(to_entry, field)
          end)

        if changed_fields == [] do
          acc
        else
          [
            %{
              test_key: key,
              before: Map.take(from_entry, @semantic_fields),
              after: Map.take(to_entry, @semantic_fields),
              changed_fields: changed_fields
            }
            | acc
          ]
        end
      end)
      |> Enum.sort_by(& &1.test_key)

    %{added: added, removed: removed, changed: changed}
  end
end
