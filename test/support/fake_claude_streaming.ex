defmodule Spotter.Test.FakeClaudeStreaming do
  @moduledoc false

  def start_session(_opts), do: {:ok, :fake_session}

  def send_message(_session, _message) do
    [
      %{type: :text_delta, text: "Hello"},
      %{type: :message_stop, final_text: "Hello"}
    ]
  end

  def close_session(_session), do: :ok
end
