defmodule RideAlong.Adept do
  @moduledoc """
  Repository for Adept data (routes/vehicles/trips).

  Also uses RideAlong.PubSub to publish updates.
  """
  use GenServer

  alias __MODULE__.Vehicle

  @default_name __MODULE__

  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, opts[:name], opts)
  end

  def all_trips(name \\ @default_name) do
    List.flatten(:ets.match(name, {{:trip, :_, :_}, :"$1"}))
  end

  def all_trips_count(name \\ @default_name) do
    :ets.select_count(name, [{{{:trip, :_, :_}, :_}, [], [true]}])
  end

  def get_trip(name \\ @default_name, trip_id) when is_integer(trip_id) do
    case :ets.match(name, {{:trip, trip_id, :_}, :"$1"}) do
      [[trip]] ->
        trip

      [] ->
        nil
    end
  end

  def get_trips_by_route(name \\ @default_name, route_id) when is_integer(route_id) do
    List.flatten(:ets.match(name, {{:trip, :_, route_id}, :"$1"}))
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
        {{:trip, trip.trip_id, trip.route_id}, trip}
      end

    trip_keys =
      :ets.select(state.table, [
        {
          {{:trip, :"$1", :"$2"}, :_},
          [],
          [{{:trip, :"$1", :"$2"}}]
        }
      ])

    for key <- trip_keys,
        not Map.has_key?(inserted_trips, key) do
      :ets.delete(state.table, key)
    end

    :ets.insert(state.table, Map.to_list(inserted_trips))

    RideAlong.PubSub.publish("trips:updated", :trips_updated)
    {:reply, :ok, state}
  end

  def handle_call({:set_vehicles, vehicles}, _from, state) do
    inserts = Map.new(vehicles, &update_vehicle(state, &1))

    vehicle_keys =
      :ets.select(state.table, [
        {
          {{:vehicle, :"$1"}, :_},
          [],
          [{{:vehicle, :"$1"}}]
        }
      ])

    for key <- vehicle_keys,
        not Map.has_key?(inserts, key) do
      :ets.delete(state.table, key)
    end

    :ets.insert(state.table, Map.to_list(inserts))

    RideAlong.PubSub.publish("vehicles:updated", :vehicles_updated)

    {:reply, :ok, state}
  end

  defp update_vehicle(state, v) do
    if old = get_vehicle_by_route(state.name, v.route_id) do
      if DateTime.compare(v.timestamp, old.timestamp) == :gt or
           Vehicle.last_stop(v) > Vehicle.last_stop(old) or
           v.vehicle_id != old.vehicle_id do
        publish_update(v)
      end
    else
      publish_update(v)
    end

    {{:vehicle, v.route_id}, v}
  end

  defp publish_update(v) do
    RideAlong.PubSub.publish(
      "vehicle:#{v.route_id}",
      {:vehicle_updated, v}
    )

    RideAlong.PubSub.publish("vehicle:all", {:vehicle_updated, v})
  end
end
