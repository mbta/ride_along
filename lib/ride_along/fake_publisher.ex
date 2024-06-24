defmodule RideAlong.FakePublisher do
  @moduledoc """
  Publishes fake data, used for local testing.
  """
  use GenServer

  alias EmqttFailover.Message
  alias Faker.Address, as: FakeAddress
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

  defstruct [:connection, interval: 5_000, topic_prefix: ""]

  @impl GenServer
  def init(_opts) do
    state = %__MODULE__{}
    {:ok, state, {:continue, :start_timers}}
  end

  @impl GenServer
  def handle_continue(:start_timers, state) do
    :timer.send_interval(state.interval, :update)
    send(self(), :update)

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
    for {name, result} <- data() do
      publish(state, name, result)
    end

    {:noreply, state}
  end

  def handle_info({:connected, connection}, %{connection: connection} = state) do
    send(self(), :update)
    {:noreply, state}
  end

  def handle_info({:disconnected, _, _reason}, state) do
    {:noreply, state}
  end

  def data do
    now = DateTime.shift_zone!(DateTime.utc_now(), Application.get_env(:ride_along, :time_zone))

    trip_id = 1234
    route_id = 2345
    vehicle_id = "5678"

    %{
      trips: [
        %{
          "Id" => trip_id,
          "TripDate" => {{now.year, now.month, now.day}, {0, 0, 0, 0}},
          "RouteId" => route_id,
          "PickTime" => Calendar.strftime(DateTime.add(now, 30, :minute), "%H:%M"),
          "PromiseTime" => "0:00",
          "PickHouseNumber" => FakeAddress.building_number(),
          "PickAddress1" => FakeAddress.street_name(),
          "PickAddress2" => FakeAddress.secondary_address(),
          "PickCity" => FakeAddress.city(),
          "PickSt" => FakeAddress.state_abbr(),
          "PickZip" => FakeAddress.zip(),
          "PickGridX" => "-7106166",
          "PickGridY" => "4234340",
          "Anchor" => "P",
          "PickOrder" => 1,
          "DropOrder" => 2,
          "PerformPickup" => 0,
          "PerformDropoff" => 0
        }
      ],
      locations: [
        %{
          "RouteId" => route_id,
          "VehicleId" => vehicle_id,
          "Heading" => 90,
          "Latitude" => 42.346,
          "Longitude" => -71.071,
          "LocationDate" =>
            {{now.year, now.month, now.day}, {now.hour, now.minute, now.second, 0}},
          "LastPick" => 0,
          "LastDrop" => 0,
          "LastArrivedTrip" => 0
        }
      ]
    }
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
