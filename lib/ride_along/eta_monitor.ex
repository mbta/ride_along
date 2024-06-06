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
    state = update_trips(%__MODULE__{})
    Phoenix.PubSub.subscribe(RideAlong.PubSub, "trips:updated")
    Phoenix.PubSub.subscribe(RideAlong.PubSub, "vehicles:updated")

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:trips_updated, state) do
    state =
      state
      |> clean_state()
      |> update_trips()

    {:noreply, state}
  end

  def handle_info(:vehicles_updated, state) do
    state = update_trips(state)

    {:noreply, state}
  end

  def clean_state(state, today \\ Date.utc_today()) do
    trip_date_to_key =
      for {{trip_id, date}, value} <- state.trip_date_to_key,
          Date.diff(date, today) >= -1,
          into: %{} do
        {{trip_id, date}, value}
      end

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

    if new_key != old_key do
      log_trip_status_change(trip, vehicle, status)
    end

    state
  end

  def log_trip_status_change(trip, vehicle, status) do
    route =
      if status not in [:arrived, :picked_up, :closed] and is_map(vehicle) do
        case RideAlong.OpenRouteService.directions(trip, vehicle) do
          {:ok, route} -> route
          _ -> nil
        end
      else
        nil
      end

    ors_eta =
      if route do
        DateTime.to_iso8601(
          DateTime.add(vehicle.timestamp, trunc(route.duration * 1000), :millisecond)
        )
      else
        nil
      end

    Logger.info(
      "#{__MODULE__} trip_id=#{trip.trip_id} route=#{trip.route_id} status=#{status} promise=#{DateTime.to_iso8601(trip.promise_time)} pick=#{DateTime.to_iso8601(trip.pick_time)} ors_eta=#{ors_eta}"
    )
  end
end
