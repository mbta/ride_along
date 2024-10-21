defmodule RideAlong.FakePublisher do
  @moduledoc """
  Publishes fake data, used for local testing.
  """
  use GenServer

  alias EmqttFailover.Message
  alias RideAlong.MqttConnection

  @default_name __MODULE__

  @trip_id 1234
  @route_id 2345
  @vehicle_id "5678"
  @destination_lat 42.351331
  @destination_lon -71.066925

  def start_link(opts) do
    if opts[:start] do
      name = Keyword.get(opts, :name, @default_name)
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      :ignore
    end
  end

  defstruct state: :enroute, interval: 15_000, topic_prefix: ""

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{}
    {:ok, state, {:continue, :start_timers}}
  end

  @impl GenServer
  def handle_continue(:start_timers, state) do
    RideAlong.PubSub.subscribe("mqtt", [:connected])
    :timer.send_interval(state.interval, :update)

    state = %{
      state
      | topic_prefix: MqttConnection.topic_prefix()
    }

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:update, state) do
    now = DateTime.shift_zone!(DateTime.utc_now(), Application.get_env(:ride_along, :time_zone))

    {results, new_state} = data(state.state, now)

    for {name, result} <- results do
      publish(state, name, result)
    end

    {:noreply, %{state | state: new_state}}
  end

  def handle_info({:connected, _}, state) do
    send(self(), :update)
    {:noreply, state}
  end

  def data(state, now)

  def data(:enroute, now) do
    results = %{
      trips: [trip(now, %{})],
      locations: [location(now, %{})]
    }

    next_state = Enum.random([:waiting, :waiting, :enroute, :arrived, :switch_vehicle])

    {results, next_state}
  end

  def data(:waiting, now) do
    results = %{
      trips: [trip(now, %{})],
      locations: [
        location(now, %{
          "Heading" => Decimal.new("0.0"),
          "Speed" => Decimal.new("0.0"),
          "Longitude" => Decimal.new("#{@destination_lon}"),
          "Latitude" => Decimal.new("#{@destination_lat}")
        })
      ]
    }

    {results, :arrived}
  end

  def data(:arrived, now) do
    results = %{
      trips: [trip(now, %{})],
      locations: [
        location(now, %{
          "Heading" => Decimal.new("0.0"),
          "Speed" => Decimal.new("0.0"),
          "Longitude" => Decimal.new("#{@destination_lon}"),
          "Latitude" => Decimal.new("#{@destination_lat}"),
          "LastArrivedTrip" => @trip_id
        })
      ]
    }

    {results, :picked_up}
  end

  def data(:switch_vehicle, now) do
    results = %{
      trips: [
        trip(now, %{
          "RouteId" => @route_id + 1,
          "PickOrder" => 3,
          "DropOrder" => 4
        })
      ],
      locations: [
        location(now, %{
          "RouteId" => @route_id + 1,
          "VehicleId" => "8675"
        })
      ]
    }

    {results, :enroute}
  end

  def data(:picked_up, now) do
    result = %{
      trips: [
        trip(now, %{
          "PerformPickup" => 2
        })
      ],
      locations: [
        location(now, %{
          "LastArrivedTrip" => @trip_id,
          "LastPick" => 2
        })
      ]
    }

    {result, :enroute}
  end

  defp trip(now, updates) do
    Map.merge(
      %{
        "Id" => @trip_id,
        "TripDate" => {{now.year, now.month, now.day}, {0, 0, 0, 0}},
        "RouteId" => @route_id,
        "ClientId" => 70_000,
        "ClientTripIndex" => 1,
        "ClientNotificationPreference" => "TEXT ONLY",
        "Status" => "S",
        "PickTime" => Calendar.strftime(DateTime.add(now, 30, :minute), "%H:%M"),
        "PromiseTime" => Calendar.strftime(DateTime.add(now, 25, :minute), "%H:%M"),
        "PickHouseNumber" => "10",
        "PickAddress1" => "Park Plaza",
        "PickAddress2" => "",
        "PickCity" => "Boston",
        "PickSt" => "MA",
        "PickZip" => "02116",
        "PickGridX" => trunc(@destination_lon * 100_000),
        "PickGridY" => trunc(@destination_lat * 100_000),
        "Anchor" => "P",
        "PickOrder" => 2,
        "DropOrder" => 3,
        "PerformPickup" => 0,
        "PerformDropoff" => 0,
        "LoadTime" => 4,
        "APtime1" => "00:00"
      },
      updates
    )
  end

  defp location(now, updates) do
    Map.merge(
      %{
        "RouteId" => @route_id,
        "VehicleId" => @vehicle_id,
        "Heading" => Decimal.new("180"),
        "Speed" => Decimal.new("15"),
        # "Latitude" => Decimal.new("42.346"),
        # "Longitude" => Decimal.new("-71.071"),
        "Longitude" => Decimal.new("-71.0126100"),
        "Latitude" => Decimal.new("42.4035100"),
        "LocationDate" => erl_dt(now),
        "LastPick" => 1,
        "LastDrop" => 1,
        "LastArrivedTrip" => nil,
        "LastDispatchArrivedTrip" => nil
      },
      updates
    )
  end

  defp erl_dt(%DateTime{} = now) do
    {{now.year, now.month, now.day}, {now.hour, now.minute, now.second, 0}}
  end

  defp publish(state, name, result) do
    MqttConnection.publish(%Message{
      topic: state.topic_prefix <> Atom.to_string(name),
      payload: :erlang.term_to_binary(result),
      qos: 1,
      retain?: true
    })
  end
end
