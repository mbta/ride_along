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

  defstruct trip_date_to_key: %{}, latest_ors_eta: %{}

  @type trip_date :: {Adept.Trip.id(), Date.t()}
  @type key :: {pick_time :: DateTime.t(), status :: Adept.Trip.status()}

  @impl GenServer
  def init(_) do
    :timer.send_interval(86_400_000, :clean_state)
    state = update_trips(%__MODULE__{})
    RideAlong.PubSub.subscribe("trips:updated")

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

    trip_ids =
      MapSet.new(trip_date_to_key, fn {{trip_id, _}, _} -> trip_id end)

    latest_ors_eta =
      Map.filter(state.latest_ors_eta, fn {trip_id, _} -> MapSet.member?(trip_ids, trip_id) end)

    %{state | trip_date_to_key: trip_date_to_key, latest_ors_eta: latest_ors_eta}
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
      log_trip_status_change(state, trip, vehicle, status, changed?)
    else
      state
    end
  end

  def log_trip_status_change(state, trip, vehicle, status, changed?) do
    route =
      if status in [:enroute, :waiting] and is_map(vehicle) do
        case RideAlong.OpenRouteService.directions(trip, vehicle) do
          {:ok, route} -> route
          _ -> nil
        end
      else
        nil
      end

    {ors_eta, ors_eta_at} =
      if route do
        {DateTime.to_iso8601(
           DateTime.add(vehicle.timestamp, trunc(route.duration * 1000), :millisecond)
         ), DateTime.to_iso8601(DateTime.utc_now())}
      else
        Map.get(state.latest_ors_eta, trip.trip_id, {nil, nil})
      end

    calculated =
      if route do
        DateTime.to_iso8601(RideAlong.EtaCalculator.calculate(trip, vehicle, route))
      end

    Logger.info(
      "#{__MODULE__} trip_id=#{trip.trip_id} route=#{trip.route_id} status=#{status} promise=#{DateTime.to_iso8601(trip.promise_time)} pick=#{DateTime.to_iso8601(trip.pick_time)} ors_eta=#{ors_eta} ors_eta_at=#{ors_eta_at} calculated_eta=#{calculated}"
    )

    if changed? do
      put_in(state.latest_ors_eta[trip.trip_id], {ors_eta, ors_eta_at})
    else
      state
    end
  end
end
