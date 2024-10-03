defmodule RideAlong.MqttConnection do
  @moduledoc """
  Shared functionality to connect to the MQTT broker.
  """
  @default_name __MODULE__

  def start_link(opts) do
    name = Keyword.get(opts, :name, @default_name)
    app_config = Keyword.merge(app_config(), opts)

    topics = [
      "#{topic_prefix()}#"
    ]

    if app_config[:start] do
      EmqttFailover.Connection.start_link(
        name: name,
        configs: app_config[:broker_configs],
        client_id: EmqttFailover.client_id(prefix: app_config[:broker_client_prefix]),
        backoff: {1_000, 60_000, :jitter},
        handler: {RideAlong.MqttConnection.PubSubHandler, topics: topics}
      )
    else
      :ignore
    end
  end

  def publish(connection \\ @default_name, message) do
    EmqttFailover.Connection.publish(connection, message)
  end

  def topic_prefix do
    app_config()[:broker_topic_prefix]
  end

  defp app_config do
    Application.get_env(:ride_along, __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end
end
