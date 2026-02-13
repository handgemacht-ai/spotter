defmodule Spotter.Config.Setting.Validations.AllowedKey do
  @moduledoc "Validates that the setting key is in the allowed set."
  use Ash.Resource.Validation

  @impl true
  def init(opts) do
    {:ok, opts}
  end

  @impl true
  def validate(changeset, opts, _context) do
    allowed = Keyword.fetch!(opts, :allowed_keys)

    case Ash.Changeset.get_attribute(changeset, :key) do
      nil ->
        :ok

      key when is_binary(key) ->
        if key in allowed do
          :ok
        else
          {
            :error,
            # credo:disable-for-next-line Credo.Check.Design.AliasUsage
            Ash.Error.Changes.InvalidAttribute.exception(
              field: :key,
              message: "must be one of: #{Enum.join(allowed, ", ")}",
              vars: %{key: key}
            )
          }
        end
    end
  end
end
