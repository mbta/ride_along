defmodule RideAlong.PubSub do
  @moduledoc """
  Pub/sub wrapper for internal Ride Along use.
  """

  def subscribe(topic, filters \\ :all) do
    Registry.register(RideAlong.Registry, topic, filters)
  end

  def unsubscribe(topic) do
    Registry.unregister(RideAlong.Registry, topic)
  end

  def publish(topic, body) do
    Registry.dispatch(RideAlong.Registry, topic, fn entries ->
      for {pid, filters} <- entries,
          matches_filters?(body, filters) do
        send(pid, body)
      end
    end)
  end

  defp matches_filters?(_body, :all) do
    true
  end

  defp matches_filters?(body, filters) do
    tag = elem(body, 0)
    tag in filters
  end
end
