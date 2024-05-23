defmodule RideAlong.Adept do
  @moduledoc """
  Repository for Adept data (routes/vehicles/trips).

  Also uses RideAlong.PubSub to publish updates.
  """
  use GenServer

  alias RideAlong.Adept.{Route, Trip, Vehicle}

  @default_name __MODULE__

  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, [], opts)
  end

  def all_trips(name \\ @default_name) do
    GenServer.call(name, :all_trips)
  end

  def get_trip(name \\ @default_name, trip_id) when is_binary(trip_id) do
    GenServer.call(name, {:get_trip, trip_id})
  end

  def get_route(name \\ @default_name, route_id) when is_binary(route_id) do
    GenServer.call(name, {:get_route, route_id})
  end

  def get_vehicle(name \\ @default_name, vehicle_id) when is_binary(vehicle_id) do
    GenServer.call(name, {:get_vehicle, vehicle_id})
  end

  defstruct [
    :routes,
    :trips,
    :vehicles
  ]

  @impl GenServer
  def init([]) do
    route_id = "r23456"
    trip_id = "t12345"
    vehicle_id = "3456"

    routes = [
      %Route{
        route_id: route_id,
        driver_name: "DRIVER, BABY",
        vehicle_id: vehicle_id
      }
    ]

    trips = [
      %Trip{
        trip_id: trip_id,
        date: Date.utc_today(),
        route_id: route_id,
        lat: 42.3516768,
        lon: -71.0695149,
        house_number: "10",
        address1: "Park Plaza",
        city: "Boston",
        phone: "+16172223200"
      }
    ]

    vehicles = [
      %Vehicle{
        vehicle_id: vehicle_id,
        lat: 42.3982372,
        lon: -71.0710461,
        timestamp: DateTime.utc_now()
      }
    ]

    state = %__MODULE__{routes: routes, trips: trips, vehicles: vehicles}
    Phoenix.PubSub.broadcast!(RideAlong.PubSub, "trips:updated", :trips_updated)

    :timer.send_interval(5_000, :update_vehicle)

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:all_trips, _from, state) do
    {:reply, state.trips, state}
  end

  @impl GenServer
  def handle_call({:get_trip, trip_id}, _from, state) do
    {:reply, Enum.find(state.trips, &(&1.trip_id == trip_id)), state}
  end

  def handle_call({:get_route, route_id}, _from, state) do
    {:reply, Enum.find(state.routes, &(&1.route_id == route_id)), state}
  end

  def handle_call({:get_vehicle, vehicle_id}, _from, state) do
    {:reply, Enum.find(state.vehicles, &(&1.vehicle_id == vehicle_id)), state}
  end

  @impl GenServer
  def handle_info(:update_vehicle, state) do
    vehicles =
      for v <- state.vehicles do
        v = %{
          v
          | lat: float_in_range(42.22786, 42.444343),
            lon: float_in_range(-71.192145, -70.951662)
        }

        Phoenix.PubSub.broadcast!(
          RideAlong.PubSub,
          "vehicle:#{v.vehicle_id}",
          {:vehicle_updated, v}
        )

        v
      end

    state = %{state | vehicles: vehicles}
    {:noreply, state}
  end

  defp float_in_range(low, high) do
    r = :rand.uniform()
    low + r * (high - low)
  end
end
