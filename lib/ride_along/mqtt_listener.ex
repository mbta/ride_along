defmodule RideAlong.MqttListener do
  @moduledoc """
  Listens for updates from MQTT topics, parses them, and updates the relevant state module.
  """
  use GenServer
  require Logger

  alias RideAlong.Adept
  alias RideAlong.MqttConnection

  @default_name __MODULE__
  def start_link(opts) do
    if opts[:start] do
      name = Keyword.get(opts, :name, @default_name)
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      :ignore
    end
  end

  defstruct [:connection]

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{}
    {:ok, state, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    topic_prefix = MqttConnection.topic_prefix()

    topics =
      for {topic, _} <- topics() do
        topic_prefix <> Atom.to_string(topic)
      end

    {:ok, connection} = MqttConnection.start_link(topics)
    state = %{state | connection: connection}
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:connected, connection}, %{connection: connection} = state) do
    {:noreply, state}
  end

  def handle_info({:message, connection, message}, %{connection: connection} = state) do
    topic_prefix = MqttConnection.topic_prefix()

    for {topic, config} <- topics(),
        message.topic == topic_prefix <> Atom.to_string(topic) do
      Task.async(__MODULE__, :parse_and_update, [topic, config, message])
    end

    {:noreply, state}
  end

  def handle_info({:disconnected, _, _reason}, state) do
    {:noreply, state}
  end

  def handle_info({ref, :parse_and_update}, state) when is_reference(ref) do
    # successful async update, nothing to do
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, pid, :normal}, state)
      when is_reference(ref) and is_pid(pid) do
    # async task stopped normally
    {:noreply, state}
  end

  def topics do
    %{
      trips: %{
        parser: &Adept.Trip.from_sql_map/1,
        update: &Adept.set_trips/1
      },
      locations: %{
        parser: &Adept.Vehicle.from_sql_map/1,
        update: &Adept.set_vehicles/1
      }
    }
  end

  defp decode_payload(<<31, 139, _::binary>> = payload) do
    decode_payload(:zlib.gunzip(payload))
  end

  defp decode_payload(<<_::binary>> = payload) do
    decode_payload(Plug.Crypto.non_executable_binary_to_term(payload))
  end

  defp decode_payload(payload) when is_list(payload) do
    %{payload: payload, id: nil}
  end

  defp decode_payload(%{} = map) do
    %{
      payload: Map.get(map, :payload, []),
      id: Map.get(map, :id)
    }
  end

  def parse_and_update(topic, config, message) do
    %{payload: payload, id: id} =
      decode_payload(message.payload)

    %{parser: parser, update: update} = config

    try do
      {parse_duration, parsed} = :timer.tc(Enum, :map, [payload, parser], :millisecond)
      {duration, _} = :timer.tc(update, [parsed], :millisecond)

      Logger.info(
        "#{__MODULE__} updated topic=#{topic} id=#{id} records=#{length(payload)} parse_duration=#{parse_duration} duration=#{duration} retain?=#{message.retain?}"
      )
    catch
      kind, e ->
        Logger.info(
          "#{__MODULE__} update failed topic=#{topic} records=#{length(payload)} error=#{inspect(e)}"
        )

        Logger.debug(Exception.format(kind, e, __STACKTRACE__))
    end

    :parse_and_update
  end
end
