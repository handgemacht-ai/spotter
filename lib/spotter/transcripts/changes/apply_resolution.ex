defmodule Spotter.Transcripts.Changes.ApplyResolution do
  @moduledoc """
  Shared Ash change that merges resolution metadata into the annotation's
  `:metadata` map. Used by both `resolve` and `mcp_resolve` actions.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    resolution =
      changeset
      |> Ash.Changeset.get_argument(:resolution)
      |> to_string()
      |> String.trim()

    if resolution == "" do
      Ash.Changeset.add_error(changeset, field: :resolution, message: "must be non-empty")
    else
      apply_resolution(changeset, resolution)
    end
  end

  defp apply_resolution(changeset, resolution) do
    kind = Ash.Changeset.get_argument(changeset, :resolution_kind)
    existing = Ash.Changeset.get_data(changeset, :metadata) || %{}

    merged =
      existing
      |> Map.put("resolution", resolution)
      |> Map.put("resolved_at", DateTime.utc_now() |> DateTime.to_iso8601())
      |> maybe_put_kind(kind)

    Ash.Changeset.change_attribute(changeset, :metadata, merged)
  end

  defp maybe_put_kind(map, nil), do: map
  defp maybe_put_kind(map, kind), do: Map.put(map, "resolution_kind", Atom.to_string(kind))
end
