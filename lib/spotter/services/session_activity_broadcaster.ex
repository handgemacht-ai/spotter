defmodule Spotter.Services.SessionActivityBroadcaster do
  @moduledoc false

  require Logger

  @topic "session_activity"

  def broadcast_started(session_id) do
    broadcast(session_id, :started)
  end

  def broadcast_finished(session_id) do
    broadcast(session_id, :finished)
  end

  defp broadcast(session_id, status) do
    Phoenix.PubSub.broadcast(
      Spotter.PubSub,
      @topic,
      {:session_activity, %{session_id: session_id, status: status}}
    )
  rescue
    e ->
      Logger.debug("SessionActivityBroadcaster: broadcast failed: #{Exception.message(e)}")
      :ok
  end
end
