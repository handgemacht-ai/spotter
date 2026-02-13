defmodule Spotter.Transcripts.Project.TimezoneValidation do
  @moduledoc "Validates that the timezone is a valid IANA timezone."
  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def validate(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.get_attribute(:timezone)
    |> validate_timezone()
  end

  defp validate_timezone(nil), do: blank_error()
  defp validate_timezone(tz) when is_binary(tz), do: tz |> String.trim() |> check_iana()

  defp check_iana(""), do: blank_error()

  defp check_iana(tz) do
    case DateTime.shift_zone(DateTime.utc_now(), tz) do
      {:ok, _} -> :ok
      _ -> {:error, invalid_error()}
    end
  end

  defp blank_error do
    {:error,
     InvalidAttribute.exception(
       field: :timezone,
       message: "must be an IANA timezone (e.g. Etc/UTC, America/Los_Angeles)"
     )}
  end

  defp invalid_error do
    InvalidAttribute.exception(
      field: :timezone,
      message: "invalid IANA timezone"
    )
  end
end
