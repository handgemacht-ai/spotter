if Application.get_env(:claude_agent_sdk, :use_mock, false) do
  {:ok, _pid} = ClaudeAgentSDK.Mock.start_link()
end

# Exclude tests that spawn Claude CLI when:
# - Running inside a Claude Code session (nested sessions crash)
# - No SPOTTER_ANTHROPIC_API_KEY set (LLM calls will fail anyway)
excludes = [:slow, :live_dolt, :live_api, :flaky]

excludes =
  if System.get_env("CLAUDECODE") || is_nil(System.get_env("SPOTTER_ANTHROPIC_API_KEY")) do
    [:spawns_claude | excludes]
  else
    excludes
  end

max_ms =
  case System.get_env("SPOTTER_TEST_MAX_MS") do
    nil ->
      1_000

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
