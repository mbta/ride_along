defmodule RideAlong.RiderNotifier do
  @moduledoc """
  Server which listens for updated trips and notifies the user about them.

  Currently, the rider is notified at the first of two events:
  - they are the next pickup for the vehicle
  - it is 30 minutes before the promise time

  In order to keep track of when the text messages have been sent, we write to
  an MQTT topic with a retained message at the sending time. If we have a
  retained message for a trip, we don't re-send a notification.
  """
  use GenServer
  require Logger

  alias EmqttFailover.Message
  alias RideAlong.Adept.Trip
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

  defstruct [:connection, :topic_prefix, date: ~D[1970-01-01], notified_trips: MapSet.new()]
  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{topic_prefix: MqttConnection.topic_prefix() <> "rider_notifier/"}
    Phoenix.PubSub.subscribe(RideAlong.PubSub, "trips:updated")
    Phoenix.PubSub.subscribe(RideAlong.PubSub, "vehicles:updated")
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
    topic_prefix = state.topic_prefix
    <<^topic_prefix::binary, topic::binary>> = message.topic

    notified_trips =
      if message.payload == "" do
        MapSet.delete(state.notified_trips, topic)
      else
        MapSet.put(state.notified_trips, topic)
      end

    state = %{state | notified_trips: notified_trips}
    {:noreply, state}
  end

  def handle_info({:disconnected, _, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(:trips_updated, state) do
    state = update_trips(state)
    {:noreply, state}
  end

  def handle_info(:vehicles_updated, state) do
    state = update_trips(state)
    {:noreply, state}
  end

  def update_trips(state) do
    DateTime.utc_now()
    |> relevant_trips()
    |> Enum.reduce(state, &maybe_notify/2)
    |> cleanup_old_topics()
  end

  defp relevant_trips(now) do
    # status is enroute/waiting (they're the next pickup) or diff is less than
    # 30m
    for trip <- RideAlong.Adept.all_trips(),
        trip.pick_time != nil,
        trip.route_id > 0,
        not trip.pickup_performed?,
        vehicle = RideAlong.Adept.get_vehicle_by_route(trip.route_id),
        diff = DateTime.diff(trip.promise_time, now),
        diff < 1800 or
          Trip.status(trip, vehicle, now) in [:enroute, :waiting, :arrived] do
      trip
    end
  end

  defp maybe_notify(trip, state) do
    topic = "#{trip.date}/#{trip.trip_id}"

    if MapSet.member?(state.notified_trips, topic) do
      state
    else
      send_notification(state, topic, trip)
    end
  end

  defp send_notification(state, topic, trip) do
    [date | _] = Enum.sort([state.date, trip.date], {:desc, Date})

    token = RideAlong.LinkShortener.get_token(trip.trip_id)

    IO.puts(
      "#{__MODULE__} generated short link route_id=#{trip.route_id} trip_id=#{trip.trip_id} token=#{token} pick_time=#{DateTime.to_iso8601(trip.pick_time)} promise_time=#{DateTime.to_iso8601(trip.promise_time)}"
    )

    MqttConnection.publish(
      state.connection,
      %Message{
        topic: state.topic_prefix <> topic,
        # need to have something in the payload
        payload: :erlang.term_to_binary({}),
        qos: 1,
        retain?: true
      }
    )

    %{state | date: date, notified_trips: MapSet.put(state.notified_trips, topic)}
  end

  defp cleanup_old_topics(state) do
    date_prefix = "#{state.date}/"

    for topic <- state.notified_trips,
        not String.starts_with?(topic, date_prefix) do
      Logger.info("#{__MODULE__} removing expired topic=#{topic}")

      MqttConnection.publish(
        state.connection,
        %Message{
          topic: state.topic_prefix <> topic,
          # unpublish the retained message
          payload: "",
          qos: 1,
          retain?: true
        }
      )
    end

    state
  end
end
