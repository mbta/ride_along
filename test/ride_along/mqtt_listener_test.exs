defmodule RideAlong.MqttListenerTest do
  @moduledoc false
  use ExUnit.Case

  alias EmqttFailover.{Connection, Message}
  alias RideAlong.MqttConnection
  alias RideAlong.MqttListener
  alias RideAlong.PubSub

  describe "start_link/1" do
    test "is ignored if start is not true" do
      assert :ignore = MqttListener.start_link(name: __MODULE__)
    end

    test "starts if provided start: true" do
      assert {:ok, _pid} = MqttListener.start_link(start: true, name: __MODULE__)
    end

    test "updates the Adept data when it receives messages" do
      PubSub.subscribe("trips:updated")

      {:ok, _} = MqttListener.start_link(start: true, name: __MODULE__)

      {%{trips: trips}, _} = RideAlong.FakePublisher.data(:enroute, DateTime.utc_now())

      message = %Message{
        topic: "#{MqttConnection.topic_prefix()}trips",
        payload:
          :erlang.term_to_binary(%{
            payload: trips,
            id: 1
          })
      }

      PubSub.publish("mqtt", {:message, %Connection{}, message})

      assert_receive :trips_updated
    end
  end
end
