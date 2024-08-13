defmodule RideAlong.PubSub do
  @moduledoc """
  Pub/sub wrapper for internal RideAlong use.
  """

  def subscribe(topic) do
    Phoenix.PubSub.subscribe(__MODULE__, topic)
  end

  def publish(topic, body) do
    Phoenix.PubSub.local_broadcast(__MODULE__, topic, body)
  end
end
