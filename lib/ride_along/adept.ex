defmodule RideAlong.Adept do
  @moduledoc """
  Repository for Adept data (routes/vehicles/trips).

  Also uses RideAlong.PubSub to publish updates.
  """
  use GenServer

  @default_name __MODULE__

  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, [], opts)
  end

  def all_trips(name \\ @default_name) do
    GenServer.call(name, :all_trips)
  end

  def get_trip(name \\ @default_name, trip_id) when is_integer(trip_id) do
    GenServer.call(name, {:get_trip, trip_id})
  end

  def set_trips(name \\ @default_name, trips) when is_list(trips) do
    GenServer.cast(name, {:set_trips, trips})
  end

  def get_vehicle_by_route(name \\ @default_name, route_id) when is_integer(route_id) do
    if route_id == 0 do
      nil
    else
      GenServer.call(name, {:get_vehicle_by_route, route_id})
    end
  end

  def set_vehicles(name \\ @default_name, vehicles) do
    GenServer.cast(name, {:set_vehicles, vehicles})
  end

  defstruct trips: %{},
            vehicles: %{}

  @impl GenServer
  def init([]) do
    state = %__MODULE__{}

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:all_trips, _from, state) do
    {:reply, Map.values(state.trips), state}
  end

  @impl GenServer
  def handle_call({:get_trip, trip_id}, _from, state) do
    {:reply, Map.get(state.trips, trip_id), state}
  end

  def handle_call({:get_vehicle_by_route, route_id}, _from, state) do
    {:reply, Map.get(state.vehicles, route_id), state}
  end

  @impl GenServer
  def handle_cast({:set_trips, trips}, state) do
    state = %{state | trips: Map.new(trips, &{&1.trip_id, &1})}
    Phoenix.PubSub.local_broadcast(RideAlong.PubSub, "trips:updated", :trips_updated)
    {:noreply, state}
  end

  def handle_cast({:set_vehicles, vehicles}, state) do
    vehicles =
      Enum.reduce(vehicles, state.vehicles, &update_vehicle/2)

    state = %{state | vehicles: vehicles}
    {:noreply, state}
  end

  defp update_vehicle(v, acc) do
    if old = Map.get(acc, v.route_id) do
      if DateTime.compare(v.timestamp, old.timestamp) == :gt or
           max(v.last_pick, v.last_drop) > max(old.last_pick, old.last_drop) do
        Phoenix.PubSub.local_broadcast(
          RideAlong.PubSub,
          "vehicle:#{v.vehicle_id}",
          {:vehicle_updated, v}
        )

        Map.put(acc, v.route_id, v)
      else
        acc
      end
    else
      Phoenix.PubSub.local_broadcast(
        RideAlong.PubSub,
        "vehicle:#{v.vehicle_id}",
        {:vehicle_updated, v}
      )

      Map.put(acc, v.route_id, v)
    end
  end
end
