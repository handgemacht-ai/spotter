defmodule Spotter.Services.ProjectRollupBucketTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.ProjectRollupBucket

  describe "bucket_key/3" do
    test "day bucket returns same local date" do
      dt = ~U[2025-06-15 10:00:00Z]
      result = ProjectRollupBucket.bucket_key(dt, "Etc/UTC", :day)
      assert result.bucket_start_date == ~D[2025-06-15]
      assert result.bucket_kind == :day
    end

    test "day bucket shifts to local timezone" do
      # 2025-06-16 02:00 UTC = 2025-06-16 04:00 Europe/Vienna
      dt = ~U[2025-06-16 02:00:00Z]
      result = ProjectRollupBucket.bucket_key(dt, "Europe/Vienna", :day)
      assert result.bucket_start_date == ~D[2025-06-16]
    end

    test "day bucket handles timezone crossing midnight" do
      # 2025-06-15 23:00 UTC = 2025-06-16 01:00 Europe/Vienna
      dt = ~U[2025-06-15 23:00:00Z]
      result = ProjectRollupBucket.bucket_key(dt, "Europe/Vienna", :day)
      assert result.bucket_start_date == ~D[2025-06-16]
    end

    test "week bucket returns Monday start (ISO)" do
      # 2025-06-18 is a Wednesday
      dt = ~U[2025-06-18 12:00:00Z]
      result = ProjectRollupBucket.bucket_key(dt, "Etc/UTC", :week)
      assert result.bucket_start_date == ~D[2025-06-16]
      assert Date.day_of_week(result.bucket_start_date) == 1
    end

    test "month bucket returns first of month" do
      dt = ~U[2025-06-18 12:00:00Z]
      result = ProjectRollupBucket.bucket_key(dt, "Etc/UTC", :month)
      assert result.bucket_start_date == ~D[2025-06-01]
    end
  end

  describe "bucket_range_utc/3" do
    test "day bucket spans 24 hours in UTC" do
      {start_utc, end_utc} =
        ProjectRollupBucket.bucket_range_utc(~D[2025-06-15], "Etc/UTC", :day)

      assert DateTime.to_date(start_utc) == ~D[2025-06-15]
      assert DateTime.to_date(end_utc) == ~D[2025-06-16]
      assert DateTime.diff(end_utc, start_utc, :second) == 86_400
    end

    test "week bucket spans 7 days" do
      {start_utc, end_utc} =
        ProjectRollupBucket.bucket_range_utc(~D[2025-06-16], "Etc/UTC", :week)

      assert DateTime.diff(end_utc, start_utc, :second) == 7 * 86_400
    end

    test "month bucket spans correct days" do
      {start_utc, end_utc} =
        ProjectRollupBucket.bucket_range_utc(~D[2025-06-01], "Etc/UTC", :month)

      assert DateTime.to_date(start_utc) == ~D[2025-06-01]
      assert DateTime.to_date(end_utc) == ~D[2025-07-01]
    end

    test "timezone offset shifts UTC range" do
      # Vienna is UTC+2 in summer
      {start_utc, _end_utc} =
        ProjectRollupBucket.bucket_range_utc(~D[2025-06-15], "Europe/Vienna", :day)

      # Midnight Vienna = 22:00 UTC previous day
      assert start_utc.hour == 22
      assert DateTime.to_date(start_utc) == ~D[2025-06-14]
    end
  end

  describe "bucket_kind_from_env/0" do
    test "defaults to :day" do
      System.delete_env("SPOTTER_PROJECT_ROLLUP_BUCKET")
      assert ProjectRollupBucket.bucket_kind_from_env() == :day
    end
  end

  describe "lookback_days_from_env/0" do
    test "defaults to 14" do
      System.delete_env("SPOTTER_PROJECT_ROLLUP_LOOKBACK_DAYS")
      assert ProjectRollupBucket.lookback_days_from_env() == 14
    end
  end
end
