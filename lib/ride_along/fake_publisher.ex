defmodule RideAlong.FakePublisher do
  @moduledoc """
  Publishes fake data, used for local testing.
  """
  use GenServer

  alias EmqttFailover.Message
  alias Faker.Address, as: FakeAddress
  alias RideAlong.MqttConnection

  @default_name __MODULE__

  @trip_id 1234
  @route_id 2345
  @vehicle_id "5678"

  def start_link(opts) do
    if opts[:start] do
      name = Keyword.get(opts, :name, @default_name)
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      :ignore
    end
  end

  defstruct [:connection, state: :enroute, interval: 15_000, topic_prefix: ""]

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{}
    {:ok, state, {:continue, :start_timers}}
  end

  @impl GenServer
  def handle_continue(:start_timers, state) do
    :timer.send_interval(state.interval, :update)

    {:noreply, state, {:continue, :connect}}
  end

  def handle_continue(:connect, state) do
    {:ok, connection} = MqttConnection.start_link()

    state = %{
      state
      | connection: connection,
        topic_prefix: MqttConnection.topic_prefix()
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

  def handle_info({:connected, connection}, %{connection: connection} = state) do
    send(self(), :update)
    {:noreply, state}
  end

  def handle_info({:disconnected, _, _reason}, state) do
    {:noreply, state}
  end

  def data(state, now)

  def data(:enroute, now) do
    results = %{
      trips: [trip(now, %{})],
      locations: [location(now, %{})]
    }

    next_state = Enum.random([:waiting, :waiting, :arrived, :arrived, :switch_vehicle])

    {results, next_state}
  end

  def data(:waiting, now) do
    results = %{
      trips: [trip(now, %{})],
      locations: [
        location(now, %{
          "Latitude" => Decimal.new("42.3434"),
          "Longitude" => Decimal.new("-71.06166")
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
      trips: [trip(now, %{})],
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
        "PickTime" => Calendar.strftime(DateTime.add(now, 30, :minute), "%H:%M"),
        "PromiseTime" => "#{now.hour}:#{now.minute}",
        "PickHouseNumber" => FakeAddress.building_number(),
        "PickAddress1" => FakeAddress.street_name(),
        "PickAddress2" => FakeAddress.secondary_address(),
        "PickCity" => FakeAddress.city(),
        "PickSt" => FakeAddress.state_abbr(),
        "PickZip" => FakeAddress.zip(),
        "PickGridX" => "-7106166",
        "PickGridY" => "4234340",
        "Anchor" => "P",
        "PickOrder" => 2,
        "DropOrder" => 3,
        "PerformPickup" => 0,
        "PerformDropoff" => 0,
        "LoadTime" => 4
      },
      updates
    )
  end

  defp location(now, updates) do
    Map.merge(
      %{
        "RouteId" => @route_id,
        "VehicleId" => @vehicle_id,
        "Heading" => Decimal.new("90"),
        "Latitude" => Decimal.new("42.346"),
        "Longitude" => Decimal.new("-71.071"),
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

  defp publish(%{connection: connection} = state, name, result) when not is_nil(connection) do
    MqttConnection.publish(
      state.connection,
      %Message{
        topic: state.topic_prefix <> Atom.to_string(name),
        payload: :erlang.term_to_binary(result),
        qos: 1,
        retain?: true
      }
    )
  end
end
