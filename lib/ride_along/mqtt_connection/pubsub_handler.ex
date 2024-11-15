defmodule RideAlong.MqttConnection.PubSubHandler do
  @moduledoc """
  Implementation of EmqttFailover.ConnectionHandler which publishes
  messages via RideAlong.PubSub
  """
  @behaviour EmqttFailover.ConnectionHandler

  alias RideAlong.PubSub

  @impl true
  def init(opts) do
    {:ok, Keyword.get(opts, :topics, [])}
  end

  @impl true
  def handle_connected(topics) do
    PubSub.publish("mqtt", {:connected, self()})
    {:ok, topics, topics}
  end

  @impl true
  def handle_disconnected(reason, topics) do
    PubSub.publish("mqtt", {:disconnected, self(), reason})
    {:ok, topics}
  end

  @impl true
  def handle_message(message, topics) do
    PubSub.publish("mqtt", {:message, self(), message})
    {:ok, topics}
  end
end
