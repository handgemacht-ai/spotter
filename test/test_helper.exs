if Application.get_env(:claude_agent_sdk, :use_mock, false) do
  {:ok, _pid} = ClaudeAgentSDK.Mock.start_link()
end

# Exclude tests that spawn Claude CLI when:
# - Running inside a Claude Code session (nested sessions crash)
# - No SPOTTER_ANTHROPIC_API_KEY set (LLM calls will fail anyway)
excludes = [:slow, :live_dolt, :live_api]

excludes =
  if System.get_env("CLAUDECODE") || is_nil(System.get_env("SPOTTER_ANTHROPIC_API_KEY")) do
    [:spawns_claude | excludes]
  else
    excludes
  end

ExUnit.start(exclude: excludes)
