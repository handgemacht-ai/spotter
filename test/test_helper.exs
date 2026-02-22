# Exclude tests that spawn Claude CLI when running inside a Claude Code session
# (nested sessions crash).
excludes = [:slow, :live_dolt, :live_api, :flaky]

excludes =
  if System.get_env("CLAUDECODE") do
    [:spawns_claude | excludes]
  else
    excludes
  end

max_ms =
  case System.get_env("SPOTTER_TEST_MAX_MS") do
    nil ->
      5_000

    val ->
      case Integer.parse(val) do
        {n, ""} when n >= 0 ->
          n

        _ ->
          raise ArgumentError,
                "SPOTTER_TEST_MAX_MS must be a non-negative integer, got: #{inspect(val)}"
      end
  end

exunit_opts = [exclude: excludes]
exunit_opts = if max_ms > 0, do: Keyword.put(exunit_opts, :timeout, max_ms), else: exunit_opts

ExUnit.start(exunit_opts)
