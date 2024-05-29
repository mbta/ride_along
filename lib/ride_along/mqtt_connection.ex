defmodule RideAlong.MqttConnection do
  @moduledoc """
  Shared functionality to connect to the MQTT broker.
  """
  def start_link(topics \\ []) do
    app_config = app_config()

    EmqttFailover.Connection.start_link(
      configs: app_config[:broker_configs],
      client_id: EmqttFailover.client_id(prefix: app_config[:broker_client_prefix]),
      backoff: {1_000, 60_000, :jitter},
      handler: {EmqttFailover.ConnectionHandler.Parent, parent: self(), topics: topics}
    )
  end

  def publish(connection, message) do
    EmqttFailover.Connection.publish(connection, message)
  end

  def topic_prefix do
    app_config()[:broker_topic_prefix]
  end

  defp app_config do
    Application.get_env(:ride_along, __MODULE__)
  end
end
