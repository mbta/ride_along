defmodule RideAlong.PubSub do
  @moduledoc """
  Pub/sub wrapper for internal RideAlong use.
  """

  def subscribe(topic) do
    Registry.register(RideAlong.Registry, topic, [])
  end

  def unsubscribe(topic) do
    Registry.unregister(RideAlong.Registry, topic)
  end

  def publish(topic, body) do
    Registry.dispatch(RideAlong.Registry, topic, fn entries ->
      for {pid, _} <- entries do
        send(pid, body)
      end
    end)
  end
end
