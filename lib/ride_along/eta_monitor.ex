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

  defstruct []

  @impl GenServer
  def init(_) do
    state = update_trips(%__MODULE__{})
    Phoenix.PubSub.subscribe(RideAlong.PubSub, "trips:updated")

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:trips_updated, state) do
    state = update_trips(state)
    {:noreply, state}
  end

  def update_trips(state) do
    now = DateTime.utc_now()

    for trip <- Enum.sort(Adept.all_trips(), Adept.Trip),
        vehicle = Adept.get_vehicle_by_route(trip.route_id),
        status = Adept.Trip.status(trip, vehicle, now),
        status != :closed do
      route =
        if status not in [:arrived, :picked_up] and is_map(vehicle) do
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

    state
  end
end
