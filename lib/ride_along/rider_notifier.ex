defmodule RideAlong.RiderNotifier do
  @moduledoc false
  use GenServer
  require Logger

  alias EmqttFailover.Message
  alias RideAlong.MqttConnection

  @default_name __MODULE__

  def start_link(opts) do
    if opts[:start] do
      name = Keyword.get(opts, :name, @default_name)
      GenServer.start_link(__MODULE__, [], name: name)
    else
      :ignore
    end
  end

  defstruct [:connection, :topic_prefix]
  @impl GenServer
  def init(_opts) do
    Logger.info("#{__MODULE__} starting")
    state = %__MODULE__{topic_prefix: MqttConnection.topic_prefix() <> "rider_notifier/"}
    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    topics = [state.topic_prefix <> "#"]
    {:ok, connection} = MqttConnection.start_link(topics)
    state = %{state | connection: connection}
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:connected, connection}, %{connection: connection} = state) do
    {:noreply, state}
  end

  def handle_info({:message, connection, message}, %{connection: connection} = state) do
    if message.payload != "" do
      Logger.info("#{__MODULE__} removing expired topic=#{message.topic}")

      MqttConnection.publish(
        state.connection,
        %Message{
          topic: message.topic,
          # unpublish the retained message
          payload: "",
          qos: 1,
          retain?: true
        }
      )
    end

    {:noreply, state}
  end

  def handle_info({:disconnected, _, _reason}, state) do
    {:noreply, state}
  end
end
