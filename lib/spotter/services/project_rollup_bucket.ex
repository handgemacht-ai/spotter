defmodule Spotter.Services.ProjectRollupBucket do
  @moduledoc """
  Timezone-safe bucket math for project rollup date-buckets.

  Supports day, week, and month granularity. Week starts on Monday (ISO).
  """

  @default_bucket_kind :day
  @default_lookback_days 14

  @doc "Returns the configured bucket kind from env or default."
  @spec bucket_kind_from_env() :: :day | :week | :month
  def bucket_kind_from_env do
    case System.get_env("SPOTTER_PROJECT_ROLLUP_BUCKET") do
      "week" -> :week
      "month" -> :month
      _ -> @default_bucket_kind
    end
  end

  @doc "Returns the configured lookback days from env or default."
  @spec lookback_days_from_env() :: pos_integer()
  def lookback_days_from_env do
    case System.get_env("SPOTTER_PROJECT_ROLLUP_LOOKBACK_DAYS") do
      nil -> @default_lookback_days
      "" -> @default_lookback_days
      val -> parse_int(val, @default_lookback_days)
    end
  end

  @doc """
  Computes the bucket key for a UTC datetime in the given timezone.

  Returns `%{bucket_start_date: Date.t(), bucket_kind: atom()}`.
  """
  @spec bucket_key(DateTime.t(), String.t(), atom()) :: %{
          bucket_start_date: Date.t(),
          bucket_kind: atom()
        }
  def bucket_key(dt_utc, tz, kind) do
    local_dt = DateTime.shift_zone!(dt_utc, tz)
    local_date = DateTime.to_date(local_dt)

    start_date =
      case kind do
        :day -> local_date
        :week -> week_start(local_date)
        :month -> Date.new!(local_date.year, local_date.month, 1)
      end

    %{bucket_start_date: start_date, bucket_kind: kind}
  end

  @doc """
  Returns the UTC range `{start_utc, end_utc}` for a bucket.

  `start_utc` is inclusive, `end_utc` is exclusive (start of next bucket).
  """
  @spec bucket_range_utc(Date.t(), String.t(), atom()) :: {DateTime.t(), DateTime.t()}
  def bucket_range_utc(bucket_start_date, tz, kind) do
    next_start =
      case kind do
        :day -> Date.add(bucket_start_date, 1)
        :week -> Date.add(bucket_start_date, 7)
        :month -> next_month_start(bucket_start_date)
      end

    start_utc = local_midnight_to_utc(bucket_start_date, tz)
    end_utc = local_midnight_to_utc(next_start, tz)

    {start_utc, end_utc}
  end

  defp week_start(date) do
    dow = Date.day_of_week(date)
    Date.add(date, -(dow - 1))
  end

  defp next_month_start(date) do
    if date.month == 12 do
      Date.new!(date.year + 1, 1, 1)
    else
      Date.new!(date.year, date.month + 1, 1)
    end
  end

  defp local_midnight_to_utc(date, tz) do
    {:ok, local_dt} = DateTime.new(date, ~T[00:00:00], tz)
    DateTime.shift_zone!(local_dt, "Etc/UTC")
  end

  defp parse_int(val, fallback) do
    case Integer.parse(String.trim(val)) do
      {int, ""} when int > 0 -> int
      _ -> fallback
    end
  end
end
