defmodule RideAlong.Adept do
  @moduledoc """
  Repository for Adept data (routes/vehicles/trips).

  Also uses RideAlong.PubSub to publish updates.
  """
  use GenServer

  @default_name __MODULE__

  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts[:name], opts)
  end

  def all_trips(name \\ @default_name) do
    List.flatten(:ets.match(name, {{:trip, :_}, :"$1"}))
  end

  def all_trips_count(name \\ @default_name) do
    :ets.select_count(name, [{{{:trip, :_}, :_}, [], [true]}])
  end

  def get_trip(name \\ @default_name, trip_id) when is_integer(trip_id) do
    case :ets.lookup(name, {:trip, trip_id}) do
      [{{:trip, ^trip_id}, trip}] ->
        trip

      [] ->
        nil
    end
  end

  def set_trips(name \\ @default_name, trips) when is_list(trips) do
    GenServer.call(name, {:set_trips, trips})
  end

  def get_vehicle_by_route(name \\ @default_name, route_id) when is_integer(route_id) do
    if route_id == 0 do
      nil
    else
      case :ets.lookup(name, {:vehicle, route_id}) do
        [{{:vehicle, ^route_id}, vehicle}] ->
          vehicle

        [] ->
          nil
      end
    end
  end

  def set_vehicles(name \\ @default_name, vehicles) do
    GenServer.call(name, {:set_vehicles, vehicles})
  end

  defstruct [:name, :table]

  @impl GenServer
  def init(name) do
    table =
      :ets.new(name, [
        :named_table,
        :set,
        :protected,
        read_concurrency: true,
        write_concurrency: :auto
      ])

    state = %__MODULE__{name: name, table: table}

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:set_trips, trips}, _from, state) do
    inserted_trips =
      for trip <- trips, into: %{} do
        {{:trip, trip.trip_id}, trip}
      end

    :ets.insert(state.table, Map.to_list(inserted_trips))

    for trip <- all_trips(state.name),
        not Map.has_key?(inserted_trips, {:trip, trip.trip_id}) do
      :ets.delete(state.table, {:trip, trip.trip_id})
    end

    Phoenix.PubSub.local_broadcast(RideAlong.PubSub, "trips:updated", :trips_updated)
    {:reply, :ok, state}
  end

  def handle_call({:set_vehicles, vehicles}, _from, state) do
    case vehicles do
      [_ | _] ->
        :ets.insert(state.table, Enum.flat_map(vehicles, &update_vehicle(state, &1)))

      [] ->
        # special case the empty list to unset all vehicles
        :ets.match_delete(state.table, {{:vehicle, :_}, :_})
    end

    Phoenix.PubSub.local_broadcast(RideAlong.PubSub, "vehicles:updated", :vehicles_updated)

    {:reply, :ok, state}
  end

  defp update_vehicle(state, v) do
    if old = get_vehicle_by_route(state.name, v.route_id) do
      if DateTime.compare(v.timestamp, old.timestamp) == :gt or
           max(v.last_pick, v.last_drop) > max(old.last_pick, old.last_drop) do
        Phoenix.PubSub.local_broadcast(
          RideAlong.PubSub,
          "vehicle:#{v.vehicle_id}",
          {:vehicle_updated, v}
        )

        [{{:vehicle, v.route_id}, v}]
      else
        []
      end
    else
      Phoenix.PubSub.local_broadcast(
        RideAlong.PubSub,
        "vehicle:#{v.vehicle_id}",
        {:vehicle_updated, v}
      )

      [{{:vehicle, v.route_id}, v}]
    end
  end
end
