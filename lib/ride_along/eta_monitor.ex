defmodule RideAlong.EtaMonitor do
  @moduledoc """
  Watches all the trips and calculates ETAs.

  We do this in order to better understand how ETAs change over time, and the
  ADEPT ETAs (pick time) compare to the ORS calculated ETAs.
  """
  use GenServer
  require Logger

  alias RideAlong.Adept

  def start_link(opts) do
    if opts[:start] do
      GenServer.start_link(__MODULE__, [])
    else
      :ignore
    end
  end

  defstruct trip_date_to_key: %{}

  @type trip_date :: {Adept.Trip.id(), Date.t()}
  @type key :: {pick_time :: DateTime.t(), status :: Adept.Trip.status()}

  @impl GenServer
  def init(_) do
    :timer.send_interval(86_400_000, :clean_state)
    state = update_trips(%__MODULE__{})
    RideAlong.PubSub.subscribe("trips:updated")
    RideAlong.PubSub.subscribe("vehicle:all")

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:trips_updated, state) do
    state =
      if RideAlong.Singleton.singleton?() do
        update_trips(state)
      else
        state
      end

    {:noreply, state}
  end

  def handle_info({:vehicle_updated, v}, state) do
    state =
      if RideAlong.Singleton.singleton?() do
        trips = Adept.get_trips_by_route(v.route_id)
        update_trips(state, trips)
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(:clean_state, state) do
    state = clean_state(state)

    {:noreply, state}
  end

  def clean_state(state, today \\ Date.utc_today()) do
    two_days_ago = Date.add(today, -2)

    trip_date_to_key =
      Map.filter(state.trip_date_to_key, fn {{_, date}, _} ->
        Date.after?(date, two_days_ago)
      end)

    %{state | trip_date_to_key: trip_date_to_key}
  end

  def update_trips(state, trips \\ Adept.all_trips(), now \\ DateTime.utc_now()) do
    trips
    |> Enum.sort(Adept.Trip)
    |> Enum.reduce(state, &update_trip(&2, &1, now))
  end

  def update_trip(state, trip, now) do
    vehicle = Adept.get_vehicle_by_route(trip.route_id)
    status = Adept.Trip.status(trip, vehicle, now)
    trip_date = {trip.trip_id, trip.date}

    new_key = {trip.pick_time, status}
    old_key = Map.get(state.trip_date_to_key, trip_date, new_key)

    state = put_in(state.trip_date_to_key[trip_date], new_key)

    changed? = new_key != old_key

    if status != :closed and (changed? or status in [:enroute, :waiting]) do
      log_trip_status_change(trip, vehicle, status, now)
    end

    state
  end

  def log_trip_status_change(trip, vehicle, status, now) do
    location_timestamp =
      if vehicle do
        vehicle.timestamp
      else
        nil
      end

    basic_metadata = [
      module: __MODULE__,
      trip_id: trip.trip_id,
      route: trip.route_id,
      status: status,
      promise: trip.promise_time,
      pick: trip.pick_time,
      pick_order: trip.pick_order,
      pick_lat: trip.lat,
      pick_lon: trip.lon,
      client_trip_index: trip.client_trip_index,
      time: location_timestamp || now,
      location: location_timestamp,
      load_time: trip.load_time,
      pickup_arrival: trip.pickup_arrival_time
    ]

    vehicle_metadata =
      with true <- status in [:enroute, :waiting],
           %{} <- vehicle do
        [
          vehicle_lat: vehicle.lat,
          vehicle_lon: vehicle.lon,
          vehicle_heading: vehicle.heading,
          vehicle_speed: vehicle.speed
        ]
      else
        _ -> []
      end

    route =
      with true <- status in [:enroute, :waiting],
           %{} <- vehicle,
           {:ok, route} <- RideAlong.OpenRouteService.directions(vehicle, trip) do
        route
      else
        _ -> nil
      end

    route_metadata =
      if route do
        ors_eta =
          if vehicle.timestamp do
            DateTime.add(vehicle.timestamp, trunc(route.duration * 1000), :millisecond)
          else
            nil
          end

        [
          ors_duration: route.duration,
          ors_heading: route.bearing,
          ors_distance: route.distance,
          ors_eta: ors_eta
        ]
      else
        []
      end

    calculated_metadata =
      if status in [:enroute, :waiting] do
        {msec, calculated} =
          :timer.tc(
            RideAlong.EtaCalculator,
            :calculate,
            [trip, vehicle, route, now],
            :millisecond
          )

        [calculated: calculated, calculated_ms: msec]
      else
        []
      end

    Logster.info(basic_metadata ++ vehicle_metadata ++ route_metadata ++ calculated_metadata)
  end
end
